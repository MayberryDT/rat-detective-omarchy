pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "StatusModel.js" as StatusModel
import "ServiceBridge.js" as ServiceBridge
import "components"

Panel {
  id: root
  moduleName: "co.animasai.rat-detective"
  ipcTarget: "co.animasai.rat-detective"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var service: null
  property bool preferencesExpanded: false
  property bool incidentExpanded: false
  property int roomIndex: 0

  readonly property var desk: service
  readonly property var barIdentity: hostWidget || root
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color background: bar ? bar.background : Color.background
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color accent: "#c79248"
  readonly property color dim: Qt.darker(foreground, 1.48)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var room: desk ? desk.selectedRoom : null
  readonly property bool roomFresh: desk ? desk.selectedRoomFresh : false
  readonly property var assignment: room ? room.assignment : null
  readonly property var rooms: desk && desk.status ? desk.status.rooms : []
  readonly property var objectiveRows: assignment ? assignment.objectiveRows.slice(0, 3) : []
  readonly property var scoreRows: room ? room.scores.slice(0, 6) : []
  readonly property string stateLine: {
    if (!desk) return "Starting the Dispatch desk…"
    if (desk.connectionState === "loading") return "Opening a line to the city…"
    if (desk.connectionState === "unavailable") return "The Dispatch desk is unavailable."
    if (desk.connectionState === "stale") return "Last report " + ageText(room ? room.localObservedAt : desk.receivedAt) + ". Clocks are paused."
    if (desk.connectionState === "empty") return "The city is quiet."
    var people = desk.totals.humans === 1 ? "1 investigator" : desk.totals.humans + " investigators"
    var rats = desk.totals.players === 1 ? "1 rat" : desk.totals.players + " rats"
    return people + " · " + rats + " · " + desk.totals.rooms + (desk.totals.rooms === 1 ? " room" : " rooms")
  }

  function ageText(stamp) {
    var seconds = Math.max(0, Math.floor((Date.now() - Number(stamp || 0)) / 1000))
    if (seconds < 5) return "just now"
    if (seconds < 60) return seconds + " seconds ago"
    var minutes = Math.floor(seconds / 60)
    return minutes === 1 ? "1 minute ago" : minutes + " minutes ago"
  }
  function resolveService() {
    if (!service) service = ServiceBridge.current()
    return service
  }
  function open() { if (desk) desk.setPanelOpen(true); root.controller.show(); Qt.callLater(function() { keyCatcher.forceActiveFocus() }) }
  function close() { if (desk) desk.setPanelOpen(false); root.controller.hide() }
  function toggle() { root.opened ? close() : open() }
  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function") return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }
  function selectRoomAt(index) {
    if (!desk || rooms.length === 0) return
    roomIndex = Math.max(0, Math.min(rooms.length - 1, index))
    desk.selectRoom(rooms[roomIndex].id)
  }
  function moveRoom(delta) { selectRoomAt(roomIndex + delta) }
  function persistSetting(name, value) { if (hostWidget && typeof hostWidget.persistSetting === "function") hostWidget.persistSetting(name, value) }
  function updateDesktopSetting(name, value) {
    persistSetting(name, value)
    var workspaceEnabled = name === "workspaceEnabled" ? value : settingBool("workspaceEnabled", false)
    var workspaceNumber = name === "workspaceNumber" ? value : settingInt("workspaceNumber", 4)
    var fullscreen = name === "fullscreen" ? value : settingBool("fullscreen", false)
    var desktopAudio = name === "desktopAudio" ? value : settingBool("desktopAudio", false)
    if (desk) desk.saveDesktopPreferences(workspaceEnabled ? workspaceNumber : 0, fullscreen, desktopAudio)
  }
  function settingBool(name, fallback) {
    var value = settings && settings[name] !== undefined ? settings[name] : fallback
    return value === true || value === "true" || value === 1
  }
  function settingInt(name, fallback) {
    var value = settings && settings[name] !== undefined ? parseInt(settings[name], 10) : fallback
    return isFinite(value) ? value : fallback
  }
  function scroll(dy) {
    var maxY = Math.max(0, contentFlick.contentHeight - contentFlick.height)
    contentFlick.contentY = Math.max(0, Math.min(maxY, contentFlick.contentY + dy * Style.space(42)))
  }
  function scrollPage(direction) {
    var maxY = Math.max(0, contentFlick.contentHeight - contentFlick.height)
    var next = contentFlick.contentY + Number(direction || 0) * Math.max(Style.space(120), contentFlick.height * 0.78)
    contentFlick.contentY = Math.max(0, Math.min(maxY, next))
    return Math.round(contentFlick.contentY) + "/" + Math.round(maxY)
  }
  function viewPreferences(show) {
    preferencesExpanded = !!show
    Qt.callLater(function() {
      if (!show) contentFlick.contentY = 0
      else {
        var maxY = Math.max(0, contentFlick.contentHeight - contentFlick.height)
        contentFlick.contentY = Math.max(0, Math.min(maxY, preferencesButton.y))
      }
    })
    return "ok"
  }

  onRoomsChanged: {
    if (!room || rooms.length === 0) roomIndex = 0
    else for (var i = 0; i < rooms.length; i++) if (rooms[i].id === room.id) roomIndex = i
  }
  onOpenedChanged: if (!opened && desk) desk.setPanelOpen(false)

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { var service = root.resolveService(); if (service) service.refresh(); return service ? "ok" : "unavailable" }
    function launch(): void { var service = root.resolveService(); if (service) service.returnToGame() }
    function fixture(name: string): string { var service = root.resolveService(); return service ? service.setFixture(name) : "unavailable" }
    function viewPreferences(show: bool): string { return root.viewPreferences(show) }
    function scrollPage(direction: int): string { return root.scrollPage(direction) }
    function snapshot(): string {
      if (!root.resolveService()) return JSON.stringify({serviceReady:false})
      return JSON.stringify({
        serviceReady: true,
        state: root.desk.connectionState,
        room: root.room ? root.room.id : null,
        counts: root.desk.totals,
        fixture: root.desk.effectiveFixture,
        renderRect: {
          x: panel.cardOrigin.x,
          y: panel.cardOrigin.y,
          width: panel.contentWidth,
          height: panel.contentHeight
        }
      })
    }
  }


  Timer {
    interval: 250
    repeat: true
    running: !root.service
    triggeredOnStart: true
    onTriggered: root.resolveService()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(390))
    contentHeight: panel.fittedContentHeight(Math.min(content.implicitHeight, Style.space(650)), Style.space(650))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) { if (dx !== 0 && root.rooms.length > 1) root.moveRoom(dx); else if (dy !== 0) root.scroll(dy) }
      onActivateRequested: if (root.desk) root.desk.returnToGame()
      onTextKey: function(text) {
        var key = String(text).toLowerCase()
        if (!root.desk) return
        if (key === "r") root.desk.refresh()
        else if (key === "p") root.desk.returnToGame()
        else if (key === "j" && root.room) root.desk.joinRoom(root.room)
        else if (key === "c") root.desk.copyLink(root.room)
        else if (key === "v") root.desk.toggleRecording()
      }

      Flickable {
        id: contentFlick
        anchors.fill: parent
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        contentWidth: width
        contentHeight: content.implicitHeight
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        QQC.ScrollBar.vertical: QQC.ScrollBar { policy: QQC.ScrollBar.AsNeeded }

        Column {
          id: content
          width: parent.width
          spacing: Style.space(11)

          Row {
            width: parent.width
            spacing: Style.space(11)
            Image { width: Style.space(42); height: width; source: Qt.resolvedUrl("icon.png"); fillMode: Image.PreserveAspectFit; mipmap: true }
            Column {
              width: parent.width - parent.children[0].width - stateBadge.width - parent.spacing * 2
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)
              Text { width: parent.width; textFormat: Text.PlainText; text: "RAT DETECTIVE"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.title; font.bold: true; font.letterSpacing: 1.1; elide: Text.ElideRight }
              Text { width: parent.width; textFormat: Text.PlainText; text: "DISPATCH DESK"; color: root.accent; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; font.letterSpacing: 1.4 }
            }
            DispatchStateBadge { id: stateBadge; anchors.verticalCenter: parent.verticalCenter; stateName: root.desk ? root.desk.connectionState : "loading"; foreground: root.foreground; urgent: root.urgent; fontFamily: root.fontFamily }
          }

          Text { width: parent.width; textFormat: Text.PlainText; text: root.stateLine; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.body; wrapMode: Text.WordWrap }

          Rectangle {
            visible: root.desk && root.desk.effectiveFixture !== ""
            width: parent.width
            height: previewText.implicitHeight + Style.space(12)
            radius: Style.cornerRadius
            color: Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.12)
            border.color: Qt.rgba(root.urgent.r, root.urgent.g, root.urgent.b, 0.55)
            Text { id: previewText; anchors.centerIn: parent; textFormat: Text.PlainText; text: "STATIC PREVIEW · " + (root.desk ? root.desk.effectiveFixture.toUpperCase() : ""); color: root.urgent; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; font.letterSpacing: 1.1 }
          }

          Rectangle {
            visible: root.desk && root.desk.limited
            width: parent.width
            height: legacyText.implicitHeight + Style.space(16)
            radius: Style.cornerRadius
            color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.11)
            border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.45)
            Text { id: legacyText; anchors.fill: parent; anchors.margins: Style.space(8); textFormat: Text.PlainText; text: "Limited server report · assignment details and city rooms are unavailable."; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
          }

          Row {
            visible: root.rooms.length > 0
            width: parent.width
            spacing: Style.space(6)
            Button { id: backRoom; visible: root.rooms.length > 1; text: "‹"; focusable: true; enabled: root.roomIndex > 0; foreground: root.foreground; fontFamily: root.fontFamily; onClicked: root.moveRoom(-1) }
            Button {
              width: parent.width - (backRoom.visible ? backRoom.width + forwardRoom.width + parent.spacing * 2 : 0)
              text: root.room ? root.room.label + "  ·  " + root.room.players + "/16" : "No active rooms"
              iconText: root.room && root.room.humans > 0 ? "●" : ""
              selected: true; focusable: true; foreground: root.foreground; accent: root.accent; fontFamily: root.fontFamily
              onClicked: if (root.rooms.length > 1) root.moveRoom(1)
            }
            Button { id: forwardRoom; visible: root.rooms.length > 1; text: "›"; focusable: true; enabled: root.roomIndex < root.rooms.length - 1; foreground: root.foreground; fontFamily: root.fontFamily; onClicked: root.moveRoom(1) }
          }

          Rectangle {
            visible: root.assignment !== null
            width: parent.width
            implicitHeight: assignmentContent.implicitHeight + Style.space(22)
            radius: Style.cornerRadius
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.055)
            border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.16)
            Column {
              id: assignmentContent
              anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; anchors.margins: Style.space(11); spacing: Style.space(5)
              Text { width: parent.width; textFormat: Text.PlainText; text: root.assignment ? root.assignment.title : ""; color: root.accent; font.family: root.fontFamily; font.pixelSize: Style.font.subtitle; font.bold: true; font.letterSpacing: 0.8; elide: Text.ElideRight }
              Text { width: parent.width; textFormat: Text.PlainText; text: root.room ? StatusModel.objectiveLine(root.room, root.desk ? root.desk.nowMs : Date.now(), root.roomFresh) : ""; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body; font.bold: true; wrapMode: Text.WordWrap }
              Text { visible: root.assignment && root.assignment.caseHolderName !== "" && root.assignment.id !== "excessive-force"; width: parent.width; textFormat: Text.PlainText; text: "Case held by " + (root.assignment ? root.assignment.caseHolderName : ""); color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption; elide: Text.ElideRight }
            }
          }

          Column {
            visible: root.objectiveRows.length > 0 && root.assignment && root.assignment.id !== "closing-time"
            width: parent.width; spacing: Style.space(8)
            PanelSectionHeader { text: "OBJECTIVE LEADERS"; foreground: root.foreground; fontFamily: root.fontFamily }
            Repeater { model: root.objectiveRows; DispatchProgressRow { required property var modelData; entry: modelData; foreground: root.foreground; accent: root.accent; fontFamily: root.fontFamily } }
          }

          Text { visible: root.desk && root.desk.connectionState === "unavailable"; width: parent.width; textFormat: Text.PlainText; text: root.desk ? root.desk.errorText : ""; color: root.urgent; font.family: root.fontFamily; font.pixelSize: Style.font.body; wrapMode: Text.WordWrap }
          PanelSeparator {}

          Row {
            width: parent.width; spacing: Style.space(7)
            Button { width: (parent.width - parent.spacing) / 2; text: root.desk && root.desk.launchPending ? "Opening…" : (root.desk && root.desk.windowOpen ? "Return to game" : "Play"); iconText: "\uf11b"; focusable: true; bordered: true; foreground: root.foreground; accent: root.accent; fontFamily: root.fontFamily; enabled: root.desk && !root.desk.desktopBusy && !root.desk.launchPending; onClicked: root.desk.returnToGame() }
            Button { width: (parent.width - parent.spacing) / 2; text: root.desk && root.desk.windowOpen ? "Join separately" : "Join room"; iconText: "\uf0c1"; focusable: true; bordered: true; foreground: root.foreground; fontFamily: root.fontFamily; enabled: root.desk && root.room && root.room.joinable && !root.desk.desktopBusy && !root.desk.limited; onClicked: root.desk.joinRoom(root.room) }
          }
          Row {
            width: parent.width; spacing: Style.space(7)
            Button { width: (parent.width - parent.spacing * 2) / 3; text: "Copy invite"; focusable: true; foreground: root.foreground; fontFamily: root.fontFamily; enabled: root.desk && !root.desk.desktopBusy; onClicked: root.desk.copyLink(root.desk.limited ? null : root.room) }
            Button { width: (parent.width - parent.spacing * 2) / 3; text: root.desk && root.desk.recording ? "Stop recording" : "Record"; focusable: true; foreground: root.foreground; fontFamily: root.fontFamily; enabled: root.desk && !root.desk.desktopBusy; onClicked: root.desk.toggleRecording() }
            Button { width: (parent.width - parent.spacing * 2) / 3; text: "Captures"; focusable: true; foreground: root.foreground; fontFamily: root.fontFamily; enabled: root.desk && !root.desk.desktopBusy; onClicked: root.desk.openCaptures() }
          }

          Button {
            visible: root.scoreRows.length > 0
            width: parent.width
            text: root.incidentExpanded ? "Hide incident log" : "Incident log · combat totals"
            iconText: root.incidentExpanded ? "\uf106" : "\uf107"
            focusable: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.incidentExpanded = !root.incidentExpanded
          }
          Column {
            visible: root.incidentExpanded && root.scoreRows.length > 0
            width: parent.width; spacing: Style.space(6)
            PanelSectionHeader { text: "KILLS / DEATHS"; foreground: root.foreground; fontFamily: root.fontFamily }
            Repeater { model: root.scoreRows; DispatchProgressRow { required property var modelData; entry: modelData; showObjective: false; foreground: root.foreground; accent: root.accent; fontFamily: root.fontFamily } }
          }

          Button { visible: root.desk && (!root.desk.launcherInstalled || !root.desk.launcherCanonical || !root.desk.launcherDurable); width: parent.width; text: root.desk && root.desk.launcherInstalled ? "Repair launcher" : "Add to app menu"; focusable: true; bordered: true; foreground: root.foreground; fontFamily: root.fontFamily; enabled: root.desk && !root.desk.desktopBusy; onClicked: root.desk.installLauncher() }
          Button { id: preferencesButton; width: parent.width; text: root.preferencesExpanded ? "Hide preferences" : "Preferences"; iconText: root.preferencesExpanded ? "\uf106" : "\uf107"; focusable: true; foreground: root.foreground; fontFamily: root.fontFamily; onClicked: root.viewPreferences(!root.preferencesExpanded) }

          Column {
            visible: root.preferencesExpanded
            width: parent.width; spacing: Style.space(8)
            Toggle { width: parent.width; label: "Dispatch alerts"; description: "Notify when investigators gather. Disabled by default."; checked: root.settingBool("alertsEnabled", false); foreground: root.foreground; accent: root.accent; fontFamily: root.fontFamily; onClicked: root.persistSetting("alertsEnabled", !checked) }
            Toggle { width: parent.width; label: "Assignment alerts"; description: "Include new assignment notices."; checked: root.settingBool("alertAssignmentChanges", false); foreground: root.foreground; accent: root.accent; fontFamily: root.fontFamily; onClicked: root.persistSetting("alertAssignmentChanges", !checked) }
            DispatchStepper { label: "Gathering threshold"; suffix: " people"; value: root.settingInt("alertHumanThreshold", 2); minimum: 1; maximum: 16; foreground: root.foreground; fontFamily: root.fontFamily; onChanged: function(value) { root.persistSetting("alertHumanThreshold", value) } }
            DispatchStepper { label: "Alert cooldown"; suffix: " min"; value: root.settingInt("alertCooldownMin", 15); minimum: 1; maximum: 1440; step: 5; foreground: root.foreground; fontFamily: root.fontFamily; onChanged: function(value) { root.persistSetting("alertCooldownMin", value) } }
            DispatchStepper { label: "Quiet hours start"; suffix: ":00"; value: root.settingInt("quietStartHour", 22); minimum: 0; maximum: 23; foreground: root.foreground; fontFamily: root.fontFamily; onChanged: function(value) { root.persistSetting("quietStartHour", value) } }
            DispatchStepper { label: "Quiet hours end"; suffix: ":00"; value: root.settingInt("quietEndHour", 8); minimum: 0; maximum: 23; foreground: root.foreground; fontFamily: root.fontFamily; onChanged: function(value) { root.persistSetting("quietEndHour", value) } }
            Toggle { width: parent.width; label: "Dedicated workspace"; description: "Move new game windows to workspace " + root.settingInt("workspaceNumber", 4) + "."; checked: root.settingBool("workspaceEnabled", false); foreground: root.foreground; accent: root.accent; fontFamily: root.fontFamily; onClicked: root.updateDesktopSetting("workspaceEnabled", !checked) }
            Row {
              visible: root.settingBool("workspaceEnabled", false); width: parent.width; spacing: Style.space(7)
              Button { text: "−"; focusable: true; foreground: root.foreground; fontFamily: root.fontFamily; enabled: root.settingInt("workspaceNumber", 4) > 1; onClicked: root.updateDesktopSetting("workspaceNumber", root.settingInt("workspaceNumber", 4) - 1) }
              Text { width: parent.width - parent.children[0].width - parent.children[2].width - parent.spacing * 2; anchors.verticalCenter: parent.verticalCenter; horizontalAlignment: Text.AlignHCenter; textFormat: Text.PlainText; text: "Workspace " + root.settingInt("workspaceNumber", 4); color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body }
              Button { text: "+"; focusable: true; foreground: root.foreground; fontFamily: root.fontFamily; enabled: root.settingInt("workspaceNumber", 4) < 10; onClicked: root.updateDesktopSetting("workspaceNumber", root.settingInt("workspaceNumber", 4) + 1) }
            }
            Toggle { width: parent.width; label: "Fullscreen new windows"; description: "Apply fullscreen after launch."; checked: root.settingBool("fullscreen", false); foreground: root.foreground; accent: root.accent; fontFamily: root.fontFamily; onClicked: root.updateDesktopSetting("fullscreen", !checked) }
            Toggle { width: parent.width; label: "Desktop audio in recordings"; description: "Microphone capture remains off."; checked: root.settingBool("desktopAudio", false); foreground: root.foreground; accent: root.accent; fontFamily: root.fontFamily; onClicked: root.updateDesktopSetting("desktopAudio", !checked) }
            PanelSectionHeader { text: "NETWORK BUDGET"; foreground: root.foreground; fontFamily: root.fontFamily }
            DispatchStepper { label: "Refresh while open"; suffix: " sec"; value: root.settingInt("openRefreshSec", 2); minimum: 2; maximum: 60; foreground: root.foreground; fontFamily: root.fontFamily; onChanged: function(value) { root.persistSetting("openRefreshSec", value) } }
            DispatchStepper { label: "Refresh while closed"; suffix: " sec"; value: root.settingInt("closedRefreshSec", 30); minimum: 10; maximum: 600; step: 5; foreground: root.foreground; fontFamily: root.fontFamily; onChanged: function(value) { root.persistSetting("closedRefreshSec", value) } }
            DispatchStepper { label: "Stale report limit"; suffix: " sec"; value: root.settingInt("staleAfterSec", 90); minimum: 30; maximum: 600; step: 15; foreground: root.foreground; fontFamily: root.fontFamily; onChanged: function(value) { root.persistSetting("staleAfterSec", value) } }
            PanelSectionHeader { text: "GAME SHORTCUT"; foreground: root.foreground; fontFamily: root.fontFamily }
            TextField { id: shortcutField; width: parent.width; placeholderText: "SUPER + SHIFT + R"; text: root.desk && root.desk.shortcutChord ? root.desk.shortcutChord : ""; font.family: root.fontFamily }
            Row {
              width: parent.width; spacing: Style.space(7)
              Button { width: (parent.width - parent.spacing) / 2; text: root.desk && root.desk.shortcutInstalled ? "Shortcut installed" : "Add shortcut"; focusable: true; bordered: true; foreground: root.foreground; fontFamily: root.fontFamily; enabled: root.desk && !root.desk.shortcutInstalled && shortcutField.text.trim() !== "" && !root.desk.desktopBusy; onClicked: root.desk.installShortcut(shortcutField.text.trim()) }
              Button { width: (parent.width - parent.spacing) / 2; text: "Remove shortcut"; focusable: true; foreground: root.foreground; fontFamily: root.fontFamily; enabled: root.desk && root.desk.shortcutInstalled && !root.desk.desktopBusy; onClicked: root.desk.removeShortcut() }
            }
          }

          Text { visible: root.desk && root.desk.actionText !== ""; width: parent.width; textFormat: Text.PlainText; text: root.desk ? root.desk.actionText : ""; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
          Text { visible: root.desk && root.desk.actionError !== ""; width: parent.width; textFormat: Text.PlainText; text: root.desk ? root.desk.actionError : ""; color: root.urgent; font.family: root.fontFamily; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap }
          Text { width: parent.width; textFormat: Text.PlainText; text: "R refresh · P play/return · J join · C copy · V record"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap }
        }
      }
    }
  }
}
