import SwiftUI

struct FlagTableView: View {
    @Binding var rows: [FlagRow]
    let isApplying: Bool

    var body: some View {
        VStack(spacing: 8) {
            Table($rows) {
                TableColumn(AppConstants.enabledColumnTitle) { $row in
                    HStack {
                        Spacer(minLength: 0)
                        Toggle("", isOn: $row.isEnabled)
                            .labelsHidden()
                        Spacer(minLength: 0)
                    }
                }
                .width(48)

                TableColumn("Flag") { $row in
                    TextField("FFlagName", text: $row.name)
                        .textFieldStyle(.roundedBorder)
                }
                .width(min: 240, ideal: 320)

                TableColumn("Value") { $row in
                    TextField("true, 120, or text", text: $row.rawValue)
                        .textFieldStyle(.roundedBorder)
                }
                .width(min: 220, ideal: 280)

                TableColumn("") { $row in
                    Button("Remove") {
                        rows.removeAll { $0.id == row.id }
                    }
                }
                .width(84)
            }
            .frame(minHeight: 360)
            .disabled(isApplying)

            HStack {
                Button("Add Flag") {
                    rows.append(FlagRow(name: "", rawValue: "true", isEnabled: true))
                }
                .disabled(isApplying)

                Spacer()
            }
        }
    }
}
