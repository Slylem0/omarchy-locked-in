import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar entry for Locked In. Filled in by later tasks.
BarWidget {
  id: root
  moduleName: Model.PLUGIN_ID

  readonly property string lang: Model.language(setting("language", "auto"), Qt.locale().name)

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\u{F051B}"
    tooltipText: Model.tr(root.lang, "tooltip")
  }
}
