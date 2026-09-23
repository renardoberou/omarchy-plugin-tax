import QtQuick
import QtQuick.Controls
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
  readonly property var pendingIds: svc ? svc.pendingIds : []
  readonly property string notice: svc ? svc.notice : ""
  readonly property var warnings: svc ? svc.auditWarnings : []
  readonly property color fg: root.bar ? root.bar.foreground : Color.foreground
  readonly property color urgentColor: root.bar ? root.bar.urgent : Color.urgent
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family

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
      color: root.alerting ? root.urgentColor : (root.bar ? root.bar.barForeground : Color.foreground)
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      textFormat: Text.PlainText
      text: root.label
      visible: !(root.bar && root.bar.vertical)
      color: root.alerting ? root.urgentColor : (root.bar ? root.bar.barForeground : Color.foreground)
      font.family: root.fontFamily
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
    contentWidth: popup.fittedContentWidth(Style.space(400))
    contentHeight: popup.fittedContentHeight(column.implicitHeight, Style.space(420))

    Column {
      id: column
      anchors.fill: parent
      spacing: Style.space(10)

      PanelHero {
        title: "Plugin Tax"
        meta: root.tip
        foreground: root.fg
        fontFamily: root.fontFamily
        iconComponent: Component {
          Rectangle {
            width: Style.space(14)
            height: Style.space(14)
            radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            color: root.alerting ? root.urgentColor : root.fg
            opacity: root.alerting ? 1.0 : 0.45
          }
        }
      }

      Text {
        width: parent.width
        visible: root.notice !== ""
        text: root.notice
        wrapMode: Text.Wrap
        color: root.urgentColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      PanelSeparator { foreground: root.fg }

      Button {
        width: parent.width
        text: root.auditing ? (svc ? svc.progressText : "Auditing…") : "Run audit"
        enabled: !root.auditing
        bordered: true
        foreground: root.fg
        horizontalPadding: Style.spacing.controlPaddingX
        verticalPadding: Style.spacing.controlPaddingY
        onClicked: if (svc) svc.runAudit("")
      }

      Text {
        width: parent.width
        visible: root.auditing
        text: "Each plugin blinks off for a few seconds and comes back where it was. Leave the shell settings alone until it finishes."
        wrapMode: Text.Wrap
        color: Qt.darker(root.fg, 1.5)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        width: parent.width
        visible: root.warnings.length > 0
        text: root.warnings.length === 1 ? root.warnings[0] : root.warnings.length + " warnings — latest: " + root.warnings[root.warnings.length - 1]
        wrapMode: Text.Wrap
        color: root.urgentColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        width: parent.width
        visible: root.auditResults.length > 0
        text: root.auditSummary + (svc && svc.auditRanAt ? " · " + Qt.formatDateTime(new Date(svc.auditRanAt), "ddd HH:mm") : "")
        wrapMode: Text.Wrap
        color: root.bar ? Qt.darker(root.bar.foreground, 1.3) : Color.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Text {
        width: parent.width
        visible: root.auditResults.length === 0 && !root.auditing
        text: "No third-party plugins to audit, or it hasn't run yet."
        wrapMode: Text.Wrap
        color: root.bar ? Qt.darker(root.bar.foreground, 1.5) : Color.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      // ListView, not a Column+Repeater: an audit can turn up more plugins
      // than fit in the popup's height cap, and a plain Column has no way to
      // scroll the overflow into view — it just renders off-card.
      ListView {
        id: resultsList
        width: parent.width
        height: Math.min(contentHeight, Style.space(240))
        spacing: Style.space(8)
        visible: root.auditResults.length > 0
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        model: root.auditResults

        delegate: Row {
          id: rowItem
          required property var modelData
          width: ListView.view.width
          spacing: Style.space(8)

          readonly property bool isOff: root.disabledIds.indexOf(modelData.id) >= 0
          readonly property bool isPending: root.pendingIds.indexOf(modelData.id) >= 0

          Rectangle {
            width: Style.space(8)
            height: Style.space(8)
            radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            color: modelData.verdict === "flagged" || modelData.verdict === "minor" ? root.urgentColor : root.fg
            opacity: rowItem.isOff ? 0.25 : (modelData.verdict === "flagged" ? 1.0 : modelData.verdict === "minor" ? 0.6 : 0.35)
          }

          Column {
            width: parent.width - Style.space(8) - rowButtons.width - 2 * rowItem.spacing
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(1)

            Text {
              textFormat: Text.PlainText
              text: modelData.name || modelData.id
              elide: Text.ElideRight
              width: parent.width
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              opacity: rowItem.isOff ? 0.5 : 1.0
            }

            Text {
              textFormat: Text.PlainText
              text: Model.formatCost(modelData) + (rowItem.isOff ? " · disabled" : "")
              width: parent.width
              elide: Text.ElideRight
              color: Qt.darker(root.fg, 1.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Row {
            id: rowButtons
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(4)

            // Re-measure just this plugin (~20s) -- e.g. after updating it,
            // or when a result is marked "within noise".
            Button {
              visible: !rowItem.isOff
              text: "Re-test"
              enabled: !rowItem.isPending && !root.auditing
              bordered: true
              foreground: root.fg
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY
              fontSize: Style.font.caption
              onClicked: if (svc) svc.runAudit(modelData.id)
            }

            Button {
              text: rowItem.isPending ? "…" : (rowItem.isOff ? "Re-enable" : "Disable")
              enabled: !rowItem.isPending && !root.auditing
              bordered: true
              foreground: root.fg
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY
              fontSize: Style.font.caption
              onClicked: if (svc) {
                if (rowItem.isOff) svc.reenablePlugin(modelData.id)
                else svc.disablePlugin(modelData.id)
              }
            }
          }
        }
      }

      Item { width: 1; height: Style.space(6) }
    }
  }
}
