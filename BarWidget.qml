import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Ui
import "ServiceBridge.js" as ServiceBridge

BarWidget {
  id: root
  moduleName: "co.animasai.rat-detective"

  property var dispatchService: null
  readonly property int playerCount: dispatchService ? dispatchService.totals.players : 0
  readonly property int humanCount: dispatchService ? dispatchService.totals.humans : 0
  readonly property string stateName: dispatchService ? dispatchService.connectionState : "loading"
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  readonly property string countLabel: stateName === "loading" ? "…"
    : stateName === "unavailable" ? "×"
    : stateName === "stale" ? "~" + playerCount : String(playerCount)
  readonly property string tooltip: {
    if (stateName === "loading") return "Rat Detective · connecting to Dispatch"
    if (stateName === "unavailable") return "Rat Detective · Dispatch unavailable"
    if (stateName === "stale") return "Rat Detective · last report is stale"
    if (stateName === "empty") return "Rat Detective · the city is quiet"
    var people = humanCount === 1 ? "1 investigator" : humanCount + " investigators"
    var rats = playerCount === 1 ? "1 rat" : playerCount + " rats"
    return "Rat Detective · " + people + " · " + rats
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function persistSetting(name, value) {
    var next = ({})
    for (var key in settings) if (key !== "id") next[key] = settings[key]
    next[name] = value
    settings = next
    if (dispatchService) dispatchService.applySettings(next)
    if (bar && bar.shell) bar.shell.updateEntryInline(moduleName, next)
  }

  function resolveDispatchService() {
    var next = ServiceBridge.current()
    if (next !== dispatchService) dispatchService = next
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("service" in target) target.service = root.dispatchService
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if (dispatchService) dispatchService.applySettings(root.settings)
  }

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
  onDispatchServiceChanged: injectPanel()
  Component.onCompleted: resolveDispatchService()

  Timer {
    interval: 250
    repeat: true
    running: !root.dispatchService
    triggeredOnStart: true
    onTriggered: root.resolveDispatchService()
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onStatusChanged: if (status === Loader.Error) console.warn("co.animasai.rat-detective panel failed; inspect the QML loader error above")
    onLoaded: { root.injectPanel(); Qt.callLater(root.injectPanel) }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // Keep a non-empty label for WidgetButton's visibility contract while the
    // branded icon/count composition supplies the visual content.
    text: " "
    labelVisible: false
    active: root.stateName === "live" && root.humanCount > 0
    dimmed: root.stateName === "loading" || root.stateName === "unavailable" || root.stateName === "stale"
    fixedWidth: root.vertical ? -1 : Math.max(Style.bar.iconSlot, Math.ceil(barContent.implicitWidth + Style.space(10)))
    tooltipText: root.tooltip
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton && root.dispatchService) root.dispatchService.refresh()
      else if (buttonCode === Qt.LeftButton || buttonCode === Qt.RightButton) root.toggle()
    }

    Item {
      id: barContent
      anchors.centerIn: parent
      implicitWidth: root.vertical ? Style.space(22) : symbol.width + count.implicitWidth + Style.space(4)
      implicitHeight: root.vertical ? Style.space(22) : Math.max(symbol.height, count.implicitHeight)
      width: implicitWidth
      height: implicitHeight

      Image {
        id: symbol
        width: root.vertical ? Style.space(18) : Style.space(17)
        height: width
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        source: Qt.resolvedUrl("assets/rat-detective-symbolic.svg")
        sourceSize.width: Math.round(width * Screen.devicePixelRatio)
        sourceSize.height: Math.round(height * Screen.devicePixelRatio)
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
        visible: false
        layer.enabled: true
      }

      MultiEffect {
        anchors.fill: symbol
        source: symbol
        autoPaddingEnabled: false
        colorization: 1.0
        colorizationColor: button.active && button.useActiveColor ? button.activeColor : button.foreground
      }

      Text {
        id: count
        anchors.right: parent.right
        y: root.vertical ? parent.height - implicitHeight : (parent.height - implicitHeight) / 2
        textFormat: Text.PlainText
        text: root.countLabel
        color: button.active && button.useActiveColor ? button.activeColor : button.foreground
        font.family: button.fontFamily
        font.pixelSize: root.vertical ? Math.max(8, Style.font.caption - 1) : Style.font.body
        font.bold: true
        renderType: Text.NativeRendering
      }
    }
  }
}
