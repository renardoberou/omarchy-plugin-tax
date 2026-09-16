import QtQuick
import Quickshell
import qs.Ui
import qs.Commons
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "renardoberou.plugin-tax"

  readonly property var svc: bar && bar.shell ? bar.shell.serviceFor("renardoberou.plugin-tax") : null
  readonly property var history: svc ? svc.history : []
  readonly property bool alerting: svc ? svc.alerting : false
  readonly property string label: svc ? svc.pillText : "Plugin Tax"
  readonly property string tip: svc ? svc.tooltip : "Plugin Tax — starting…"
  readonly property bool auditing: svc ? svc.auditing : false
  readonly property var auditResults: svc ? svc.auditResults : []
  readonly property string auditSummary: svc ? svc.auditSummary : ""
  readonly property var disabledIds: svc ? svc.disabledIds : []

  property bool popupOpen: false
  function close() { popupOpen = false }

  implicitWidth: pillRow.implicitWidth + Style.space(14)
  implicitHeight: barSize

  Row {
    id: pillRow
    anchors.centerIn: parent
    spacing: Style.space(4)

    Text {
      textFormat: Text.PlainText
      text: root.alerting ? "⚡" : "󰾆"
      color: root.alerting ? (root.bar ? root.bar.urgent : Color.urgent) : root.bar.barForeground
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.body
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      textFormat: Text.PlainText
      text: root.label
      visible: !root.bar.vertical
      color: root.alerting ? (root.bar ? root.bar.urgent : Color.urgent) : root.bar.barForeground
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.body
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.popupOpen = !root.popupOpen
    onEntered: if (root.bar) root.bar.showTooltip(root, root.tip)
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }

  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(340))
    contentHeight: popup.fittedContentHeight(column.implicitHeight, Style.space(420))

    Column {
      id: column
      anchors.fill: parent
      spacing: Style.space(10)

      PanelHero {
        title: "Plugin Tax"
        meta: root.tip
        foreground: root.bar ? root.bar.foreground : Color.foreground
        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
        iconComponent: Component {
          Rectangle {
            width: Style.space(14)
            height: Style.space(14)
            radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            color: root.alerting ? (root.bar ? root.bar.urgent : Color.urgent) : "#5fd68a"
          }
        }
      }

      PanelSeparator { foreground: root.bar ? root.bar.foreground : Color.foreground }

      Button {
        width: parent.width
        text: root.auditing ? "Auditing… (blinks each plugin off briefly)" : "Run audit"
        enabled: !root.auditing
        bordered: true
        foreground: root.bar ? root.bar.foreground : Color.foreground
        horizontalPadding: Style.spacing.controlPaddingX
        verticalPadding: Style.spacing.controlPaddingY
        onClicked: if (svc) svc.runAudit()
      }

      Text {
        width: parent.width
        visible: root.auditResults.length > 0
        text: root.auditSummary
        wrapMode: Text.Wrap
        color: root.bar ? Qt.darker(root.bar.foreground, 1.3) : Color.muted
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.bodySmall
      }

      Text {
        width: parent.width
        visible: root.auditResults.length === 0 && !root.auditing
        text: "No third-party plugins to audit, or it hasn't run yet."
        wrapMode: Text.Wrap
        color: root.bar ? Qt.darker(root.bar.foreground, 1.5) : Color.muted
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
      }

      Column {
        width: parent.width
        spacing: Style.space(8)
        visible: root.auditResults.length > 0

        Repeater {
          model: root.auditResults

          Row {
            id: rowItem
            required property var modelData
            width: parent.width
            spacing: Style.space(8)

            readonly property bool isOff: root.disabledIds.indexOf(modelData.id) >= 0

            Rectangle {
              width: Style.space(8)
              height: Style.space(8)
              radius: width / 2
              anchors.verticalCenter: parent.verticalCenter
              color: modelData.flagged ? (root.bar ? root.bar.urgent : Color.urgent) : "#5fd68a"
              opacity: rowItem.isOff ? 0.35 : 1.0
            }

            Column {
              width: parent.width - Style.space(120)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(1)

              Text {
                textFormat: Text.PlainText
                text: modelData.name || modelData.id
                elide: Text.ElideRight
                width: parent.width
                color: root.bar ? root.bar.foreground : Color.foreground
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.bodySmall
                opacity: rowItem.isOff ? 0.5 : 1.0
              }

              Text {
                textFormat: Text.PlainText
                text: (modelData.deltaPct >= 0 ? "+" : "") + Number(modelData.deltaPct).toFixed(1) +
                  "% cpu idle" + (rowItem.isOff ? " · disabled" : "")
                color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.4)
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
              }
            }

            Button {
              anchors.verticalCenter: parent.verticalCenter
              text: rowItem.isOff ? "Off" : "Disable"
              enabled: !rowItem.isOff
              bordered: true
              foreground: root.bar ? root.bar.foreground : Color.foreground
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY
              fontSize: Style.font.caption
              onClicked: if (svc) svc.disablePlugin(modelData.id)
            }
          }
        }
      }

      Item { width: 1; height: Style.space(6) }
    }
  }
}
