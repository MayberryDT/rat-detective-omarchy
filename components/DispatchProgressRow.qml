import QtQuick
import qs.Commons

Column {
  id: root
  required property var entry
  property color foreground: Color.foreground
  property color accent: "#c79248"
  property string fontFamily: Style.font.family
  property bool showObjective: true
  width: parent ? parent.width : implicitWidth
  spacing: Style.space(3)

  Row {
    width: parent.width
    spacing: Style.space(8)
    Text {
      textFormat: Text.PlainText
      width: parent.width - score.implicitWidth - parent.spacing
      text: root.entry.name
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.bold: root.entry.holder === true
      elide: Text.ElideRight
    }
    Text {
      id: score
      textFormat: Text.PlainText
      text: root.showObjective && root.entry.target > 0
        ? root.entry.points + " / " + root.entry.target
        : root.entry.kills + "K  " + root.entry.deaths + "D"
      color: Qt.darker(root.foreground, 1.35)
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.bold: root.showObjective
    }
  }

  Rectangle {
    visible: root.showObjective && root.entry.target > 0
    width: parent.width
    height: Style.space(4)
    radius: height / 2
    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14)
    Rectangle {
      width: parent.width * Math.max(0, Math.min(1, root.entry.points / Math.max(1, root.entry.target)))
      height: parent.height
      radius: height / 2
      color: root.accent
      Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    }
  }
}
