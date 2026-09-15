import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFile} from 'node:fs/promises';

async function loadModel(){
  const source=await readFile(new URL('../StatusModel.js',import.meta.url),'utf8');
  const context={module:{exports:{}},Date,JSON,Math,Number,String,Array,Object,isFinite};
  vm.runInNewContext(source,context,{filename:'StatusModel.js'});
  return context.module.exports;
}

const paperRoom={
  room:'public-live-v2',generation:1,revision:7,roundId:'round-paper',
  observedAt:1_000_000,expiresAt:1_060_000,players:8,humans:3,
  assignment:{id:'chain-of-custody',title:'PAPER CHASE',phase:'active',remainingMs:null,clockRunning:false,
    objectiveTarget:3,objectiveUnit:'deliveries',destination:{id:'records',label:'RECORDS BUREAU'},zone:null,nextZone:null,zoneRemainingMs:null},
  scores:[{id:'a',name:'Ada',kills:1,deaths:1,objectiveScore:2},{id:'b',name:'Basil',kills:3,deaths:2,objectiveScore:1}],
  holderName:'Ada',result:null
};

test('normalizes assignment status and preserves objective ordering',async()=>{
  const model=await loadModel();
  const status=model.normalizeV1({schemaVersion:1,observedAt:1_000_000,rooms:[paperRoom]},1_000_100);
  assert.equal(status.rooms.length,1);
  assert.equal(status.rooms[0].players,8);
  assert.equal(status.rooms[0].assignment.id,'chain-of-custody');
  assert.equal(status.rooms[0].assignment.objectiveRows[0].name,'Ada');
  assert.equal(model.objectiveLine(status.rooms[0],1_000_500,true),'Deliver to RECORDS BUREAU');
  assert.deepEqual({...model.totals(status)},{rooms:1,players:8,humans:3});
  assert.equal(model.publicRoomLabel('public-live-v2-12345678-1234-4234-9234-123456789abc',1),'City 12345678');
});

test('merges paginated rooms by generation and revision without duplicates',async()=>{
  const model=await loadModel();
  const first=model.normalizeV1({schemaVersion:1,observedAt:1_000_000,nextCursor:'page-2',rooms:[paperRoom]},1_000_000);
  const changed={...paperRoom,generation:2,revision:8,players:9,humans:4};
  const overflow={...paperRoom,room:'public-live-v2-overflow-1',generation:2,revision:1,roundId:'round-zone'};
  const second=model.normalizeV1({schemaVersion:1,observedAt:1_000_010,rooms:[changed,overflow]},1_000_010);
  const merged=model.mergePages(first,second);
  assert.equal(merged.rooms.length,2);
  assert.equal(model.roomById(merged,'public-live-v2').players,9);
  assert.equal(merged.nextCursor,'');
  const olderGeneration=model.normalizeV1({schemaVersion:1,observedAt:1_000_020,rooms:[{...paperRoom,generation:1,revision:999,players:2}]},1_000_020);
  assert.equal(model.mergePages(merged,olderGeneration).rooms.find(room=>room.id==='public-live-v2').players,9);
  assert.equal(model.roomById(merged,'retired-room'),null);
});

test('distinguishes loading, live, empty, stale and unavailable',async()=>{
  const model=await loadModel();
  assert.equal(model.connectionState(null,0,1000,500,false),'loading');
  assert.equal(model.connectionState(null,0,1000,500,true),'unavailable');
  const live=model.normalizeV1({schemaVersion:1,observedAt:1000,rooms:[{...paperRoom,observedAt:1000}]},1000);
  assert.equal(model.connectionState(live,1000,1200,500,false),'live');
  assert.equal(model.connectionState(live,1000,1600,500,false),'stale');
  assert.equal(model.connectionState(live,1000,1200,500,true),'stale');
  const empty=model.normalizeV1({schemaVersion:1,observedAt:1000,rooms:[]},1000);
  assert.equal(model.connectionState(empty,1000,1200,500,false),'empty');
});

test('countdowns advance only while fresh and running, never below zero',async()=>{
  const model=await loadModel();
  assert.equal(model.displayRemaining(10_000,1000,4000,true,true),7000);
  assert.equal(model.displayRemaining(10_000,1000,4000,true,false),10_000);
  assert.equal(model.displayRemaining(10_000,1000,4000,false,true),10_000);
  assert.equal(model.displayRemaining(1000,1000,4000,true,true),0);
  assert.equal(model.formatClock(65_000),'1:05');
});

test('server timestamps are anchored to local receipt time despite clock skew',async()=>{
  const model=await loadModel();
  const serverNow=9_000_000;
  const localNow=2_000;
  const status=model.normalizeV1({schemaVersion:1,observedAt:serverNow,rooms:[{...paperRoom,observedAt:serverNow-500,expiresAt:serverNow+74_500,assignment:{...paperRoom.assignment,id:'closing-time',title:'CLOSING TIME',remainingMs:10_000,clockRunning:true,objectiveTarget:null,objectiveUnit:'last-holder',destination:null}}]},localNow);
  const room=status.rooms[0];
  assert.equal(room.localObservedAt,1500);
  assert.equal(model.objectiveLine(room,4500,true),'0:07 remaining');
  assert.equal(model.roomFresh(room,76_400),true);
  assert.equal(model.roomFresh(room,76_600),false);
});

test('legacy status stays explicitly limited',async()=>{
  const model=await loadModel();
  const status=model.normalizeLegacy({room:'public',players:2,phase:'playing',scores:[{name:'Marlowe',kills:4,deaths:3}]},1000);
  assert.equal(status.limited,true);
  assert.equal(status.rooms[0].assignment.id,'');
  assert.equal(status.rooms[0].scores[0].kills,4);
  assert.equal(model.connectionState(status,1000,75_999,90_000,false),'live');
});

test('alerts baseline, suppressions, thresholds, dedupe and cooldown are deterministic',async()=>{
  const model=await loadModel();
  const previous=model.normalizeV1({schemaVersion:1,observedAt:1000,rooms:[{...paperRoom,humans:1}]},1000);
  const current=model.normalizeV1({schemaVersion:1,observedAt:2000,rooms:[paperRoom]},2000);
  const settings={alertsEnabled:true,alertHumanThreshold:2,quietStartHour:0,quietEndHour:0};
  assert.equal(model.alertEvents(null,current,settings,2_000,{fresh:true}).length,0);
  const events=model.alertEvents(previous,current,settings,2_000,{fresh:true});
  assert.equal(events.length,1);
  assert.equal(model.alertEvents(previous,current,settings,2_000,{fresh:true,gameFocused:true}).length,0);
  assert.equal(model.alertEvents(previous,current,settings,2_000,{fresh:true,dnd:true}).length,0);
  const accepted=model.filterAlertReceipts(events,{},2_000,60_000);
  assert.equal(accepted.events.length,1);
  assert.equal(model.filterAlertReceipts(events,accepted.receipts,3_000,60_000).events.length,0);
});

test('Jurisdiction hides the next zone until warning and freezes stale countdowns',async()=>{
  const model=await loadModel();
  const base={...paperRoom,observedAt:1000,expiresAt:76000,roundId:'zone-round',assignment:{id:'jurisdiction',title:'JURISDICTION',phase:'active',remainingMs:null,clockRunning:false,objectiveTarget:60,objectiveUnit:'seconds',destination:null,zone:{id:'icebox',label:'THE ICEBOX'},nextZone:null,zoneRemainingMs:10_000}};
  const quiet=model.normalizeV1({schemaVersion:1,observedAt:1000,rooms:[base]},1000).rooms[0];
  assert.equal(model.objectiveLine(quiet,4000,true),'Hold the case in THE ICEBOX');
  const warning=model.normalizeV1({schemaVersion:1,observedAt:1000,rooms:[{...base,assignment:{...base.assignment,nextZone:{id:'sluice',label:'WEST SLUICE'}}}]},1000).rooms[0];
  assert.equal(model.objectiveLine(warning,4000,true),'Relocating to WEST SLUICE in 0:07');
  assert.equal(model.objectiveLine(warning,4000,false),'Relocating to WEST SLUICE in 0:10');
});

test('bundled static previews cover all assignments and connectivity reports',async()=>{
  const model=await loadModel();
  const bundle=JSON.parse(await readFile(new URL('../fixtures/dispatch.json',import.meta.url),'utf8'));
  const assignments=new Set();
  for(const name of ['paper','jurisdiction','excessive','closing','stale']){
    const status=model.normalizeV1(bundle.fixtures[name],10_000);
    assert.equal(status.rooms.length,1,name);
    assignments.add(status.rooms[0].assignment.id);
  }
  assert.deepEqual([...assignments].sort(),['chain-of-custody','closing-time','excessive-force','jurisdiction']);
  assert.equal(model.normalizeV1(bundle.fixtures.empty,10_000).rooms.length,0);
});

function noon(){
  const date=new Date();
  date.setHours(12,0,0,0);
  return date.getTime();
}

function night(){
  const date=new Date();
  date.setHours(23,0,0,0);
  return date.getTime();
}

function overflowRoom(humans,observedAt,expiresAt){
  return {
    ...paperRoom,
    room:'public-live-v2-aaaaaaaa-1234-4234-9234-123456789abc',
    humans,
    players:Math.max(humans,1),
    observedAt,
    expiresAt,
    roundId:'round-overflow'
  };
}

test('a new fresh room meeting the gathering threshold after baseline alerts',async()=>{
  const model=await loadModel();
  const settings={alertsEnabled:true,alertHumanThreshold:2,quietStartHour:0,quietEndHour:0};
  const baseline=model.normalizeV1({schemaVersion:1,observedAt:1000,rooms:[{...paperRoom,humans:1}]},1000);
  const arrived=model.normalizeV1({schemaVersion:1,observedAt:2000,rooms:[{...paperRoom,humans:1},overflowRoom(2,2000,77_000)]},2000);
  assert.equal(model.alertEvents(null,arrived,settings,2000,{fresh:true}).length,0,'first snapshot stays silent');
  const events=model.alertEvents(baseline,arrived,settings,2000,{fresh:true});
  assert.equal(events.length,1);
  assert.match(events[0].body,/2 human/);
  assert.match(events[0].body,/City aaaaaaaa|Public room/);
  const staleArrival=model.normalizeV1({schemaVersion:1,observedAt:2000,rooms:[{...paperRoom,humans:1},overflowRoom(2,1000,1100)]},2000);
  assert.equal(model.alertEvents(baseline,staleArrival,settings,2500,{fresh:true}).length,0,'stale new rooms stay silent');
  assert.equal(model.alertEvaluateMode(false,'loading','live'),'baseline');
  assert.equal(model.alertEvaluateMode(true,'stale','live'),'baseline');
  assert.equal(model.alertEvaluateMode(true,'live','live'),'evaluate');
});

test('stale occupancy cannot claim a live city',async()=>{
  const model=await loadModel();
  const staleOccupied={...paperRoom,observedAt:1000,expiresAt:1100,players:8,humans:3};
  const freshEmpty=overflowRoom(0,1000,5000);
  freshEmpty.players=0;
  freshEmpty.scores=[];
  const mixed=model.normalizeV1({schemaVersion:1,observedAt:1000,rooms:[staleOccupied,freshEmpty]},1000);
  assert.equal(model.connectionState(mixed,1000,1500,90_000,false),'empty');
  const fresh=model.freshTotals(mixed,1500);
  assert.equal(fresh.rooms,1);
  assert.equal(fresh.players,0);
  assert.equal(fresh.humans,0);
  assert.equal(model.displayTotals(mixed,1500,'empty').players,0);
  assert.equal(model.displayTotals(mixed,1500,'stale').players,8);
});

test('open refresh asks for the current active public page and is not dropped in flight',async()=>{
  const model=await loadModel();
  const base='https://ratdetective.online/api/companion/v1/status';
  assert.equal(model.companionStatusUrl(base,'',16),base+'?limit=16');
  assert.equal(model.companionStatusUrl(base,'page-2',16),base+'?limit=16&cursor=page-2');
  assert.equal(model.refreshAction({locked:true,fixture:'',requestRunning:false}),'skip');
  assert.equal(model.refreshAction({locked:false,fixture:'',requestRunning:true}),'defer');
  assert.equal(model.refreshAction({locked:false,fixture:'',requestRunning:false}),'start');
  assert.equal(model.refreshAction({locked:true,fixture:'paper',requestRunning:false}),'start');
  assert.equal(model.finishRefreshAction(true),'start');
  assert.equal(model.finishRefreshAction(false),'schedule');
  assert.equal(model.pollDelayMs(true,2000,30_000,0),2000);
  assert.equal(model.pollDelayMs(false,2000,30_000,0),30_000);
});

test('schema still accepts sixteen rats while a ten-rat city stays valid',async()=>{
  const model=await loadModel();
  const tenScores=Array.from({length:10},(_,index)=>({id:'p'+index,name:'Rat '+index,kills:0,deaths:0,objectiveScore:0}));
  const ten=model.normalizeV1({schemaVersion:1,observedAt:1000,rooms:[{...paperRoom,players:10,humans:8,scores:tenScores}]},1000);
  assert.equal(ten.rooms[0].players,10);
  assert.equal(ten.rooms[0].humans,8);
  assert.equal(ten.rooms[0].capacity,16);
  const sixteenScores=Array.from({length:16},(_,index)=>({id:'p'+index,name:'Rat '+index,kills:0,deaths:0,objectiveScore:0}));
  const sixteen=model.normalizeV1({schemaVersion:1,observedAt:1000,rooms:[{...paperRoom,players:16,humans:16,scores:sixteenScores}]},1000);
  assert.equal(sixteen.rooms[0].players,16);
  assert.equal(sixteen.rooms[0].humans,16);
});

test('alert status explains disabled, DND, quiet, focus, stale, baseline and cooldown',async()=>{
  const model=await loadModel();
  const armed={alertsEnabled:true,alertHumanThreshold:2,alertAssignmentChanges:true,quietStartHour:22,quietEndHour:8};
  const live={fresh:true,baselineReady:true,connectionState:'live',desktopReady:true,gameFocused:false,dnd:false,locked:false,fixture:false};
  const off=model.alertWatchStatus({alertsEnabled:false},noon(),live,{},900_000);
  assert.equal(off.text,'Alerts: off');
  assert.match(off.detail,/enable/i);
  const dnd=model.alertWatchStatus(armed,noon(),{...live,dnd:true},{},900_000);
  assert.equal(dnd.text,'Alerts paused: Do not disturb');
  assert.match(dnd.detail,/Do Not Disturb|do not disturb/i);
  const quiet=model.alertWatchStatus(armed,night(),live,{},900_000);
  assert.equal(quiet.text,'Alerts paused: quiet hours');
  assert.match(quiet.detail,/22:00/);
  const focus=model.alertWatchStatus(armed,noon(),{...live,gameFocused:true},{},900_000);
  assert.equal(focus.text,'Alerts paused: in game');
  assert.match(focus.detail,/focused/i);
  const stale=model.alertWatchStatus(armed,noon(),{...live,fresh:false,connectionState:'stale'},{},900_000);
  assert.equal(stale.text,'Alerts paused: stale report');
  assert.match(stale.detail,/stale/i);
  const baseline=model.alertWatchStatus(armed,noon(),{...live,baselineReady:false},{},900_000);
  assert.equal(baseline.text,'Alerts: establishing baseline');
  assert.match(baseline.detail,/first|silent|replay/i);
  const cooldown=model.alertWatchStatus(armed,noon(),live,{'gathering:public-live-v2:round-paper:2':noon()-60_000},900_000);
  assert.equal(cooldown.text,'Alerts paused: cooling down');
  assert.match(cooldown.detail,/sent recently|cooldown/i);
  const watching=model.alertWatchStatus(armed,noon(),live,{},900_000);
  assert.equal(watching.text,'Alerts: watching the city');
  assert.match(watching.detail,/2 investigator/);
  assert.match(watching.detail,/assignment/i);
  const notReady=model.alertWatchStatus(armed,noon(),{...live,connectionState:'loading',fresh:false,desktopReady:false},{},900_000);
  assert.equal(notReady.text,'Alerts paused: not ready');
});

test('queued notices reserve receipts until sent, suppressed, or exhausted',async()=>{
  const model=await loadModel();
  const settings={alertsEnabled:true,alertHumanThreshold:2,quietStartHour:0,quietEndHour:0};
  const live={fresh:true,baselineReady:true,desktopReady:true};
  assert.equal(model.noticeDeliverable(settings,noon(),live),true);
  assert.equal(model.noticeDeliverable(settings,noon(),{...live,dnd:true}),false);
  assert.equal(model.noticeDeliverable(settings,noon(),{...live,gameFocused:true}),false);
  const events=[{key:'gathering:public-live-v2:round-paper:2',title:'Rats are gathering',body:'2 human investigators in Public city'}];
  const claimed=model.filterAlertReceipts(events,{},1000,900_000);
  assert.equal(claimed.events.length,1);
  assert.equal(model.receiptState(claimed.receipts,events[0].key),'reserved');
  const failed=model.advanceNoticeQueue(claimed.events,claimed.receipts,'failed',1100);
  assert.equal(failed.queue.length,1);
  assert.equal(model.receiptState(failed.receipts,events[0].key),'reserved');
  const stillQueued=model.filterAlertReceipts(events,failed.receipts,2000,900_000,{[events[0].key]:true});
  assert.equal(stillQueued.events.length,0,'a queued retry is not enlisted twice');
  const reservedBlocks=model.filterAlertReceipts(events,failed.receipts,2000,900_000);
  assert.equal(reservedBlocks.events.length,0,'reservation keeps cooldown and dedup');
  const waiting=model.alertWatchStatus({alertsEnabled:true,alertHumanThreshold:2,quietStartHour:0,quietEndHour:0},noon(),{...live,deliveryPending:true},failed.receipts,900_000);
  assert.equal(waiting.text,'Alerts paused: waiting to deliver');
  assert.match(waiting.detail,/not been delivered|waiting/i);
  const reservedOnly=model.alertWatchStatus({alertsEnabled:true,alertHumanThreshold:2,quietStartHour:0,quietEndHour:0},noon(),live,failed.receipts,900_000);
  assert.notEqual(reservedOnly.text,'Alerts paused: cooling down');
  const sent=model.advanceNoticeQueue(failed.queue,failed.receipts,'sent',5000);
  assert.equal(sent.queue.length,0);
  assert.equal(model.receiptState(sent.receipts,events[0].key),'sent');
  assert.equal(model.receiptTime(sent.receipts,events[0].key),5000);
  const afterSend=model.filterAlertReceipts(events,sent.receipts,5200,900_000);
  assert.equal(afterSend.events.length,0);
  const cooling=model.alertWatchStatus({alertsEnabled:true,alertHumanThreshold:2,quietStartHour:0,quietEndHour:0},5200,live,sent.receipts,900_000);
  assert.equal(cooling.text,'Alerts paused: cooling down');
  const suppressed=model.advanceNoticeQueue(events,claimed.receipts,'suppressed',1300);
  assert.equal(suppressed.queue.length,0);
  assert.equal(model.receiptState(suppressed.receipts,events[0].key),'');
});

test('helper JSON commits only an actual sent action',async()=>{
  const model=await loadModel();
  assert.equal(model.classifyNotifyResult(0,'{"ok":true,"action":"sent"}'),'sent');
  assert.equal(model.classifyNotifyResult(0,'{"ok":true,"action":"suppressed-dnd"}'),'suppressed');
  assert.equal(model.classifyNotifyResult(0,'{"ok":true,"action":"suppressed-focused"}'),'suppressed');
  assert.equal(model.classifyNotifyResult(0,'{"ok":false,"action":"failed","error":"notify missing"}'),'failed');
  assert.equal(model.classifyNotifyResult(0,'{"ok":false,"error":"busy"}'),'failed');
  assert.equal(model.classifyNotifyResult(0,''),'failed');
  assert.equal(model.classifyNotifyResult(1,'{"ok":false,"action":"failed"}'),'failed');
});

test('multiple events share one cooldown and fixture clears only reservations',async()=>{
  const model=await loadModel();
  const first={key:'gathering:public-live-v2:round-paper:2',title:'Rats are gathering',body:'2 human investigators in Public city'};
  const second={key:'gathering:public-live-v2-aaaaaaaa-1234-4234-9234-123456789abc:round-overflow:2',title:'Rats are gathering',body:'2 human investigators in City aaaaaaaa'};
  const accepted=model.filterAlertReceipts([first,second],{},1000,60_000);
  assert.equal(accepted.events.length,1);
  assert.equal(accepted.events[0].key,first.key);
  const later=model.filterAlertReceipts([second],accepted.receipts,2000,60_000);
  assert.equal(later.events.length,0);
  const reserved=model.filterAlertReceipts([first],{},3000,60_000);
  const sent=model.advanceNoticeQueue(reserved.events,reserved.receipts,'sent',4000);
  const leftover=model.filterAlertReceipts([second],sent.receipts,4100,60_000);
  leftover.receipts['gathering:pending:round:2']={at:4100,state:'reserved'};
  const cleared=model.clearNoticeEffects([first,second],leftover.receipts);
  assert.equal(cleared.queue.length,0);
  assert.equal(model.receiptState(cleared.receipts,first.key),'sent');
  assert.equal(model.receiptState(cleared.receipts,'gathering:pending:round:2'),'');
  assert.equal(model.boundedNoticeQueue(new Array(12).fill(first)).length,8);
});
