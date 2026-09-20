import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \SolveRecord.startedAt, order: .reverse) private var records: [SolveRecord]
    @Environment(\.modelContext) private var context
    @State private var statsSize = 3

    private var sizeOptions: [Int] {
        var sizes = Set([3])
        sizes.formUnion(records.map(\.cubeSize))
        return sizes.sorted()
    }

    /// 参与统计的记录：筛选阶数；列表仍展示全部
    private var statsRecords: [SolveRecord] {
        records.filter { $0.cubeSize == statsSize }
    }

    var body: some View {
        Group {
            if records.isEmpty {
                ContentUnavailableView("还没有记录",
                                       systemImage: "stopwatch",
                                       description: Text("在「练习」页打乱并复原一次魔方，成绩会自动记在这里"))
            } else {
                List {
                    Section {
                        statsRow
                        if sizeOptions.count > 1 {
                            Picker("阶数", selection: $statsSize) {
                                ForEach(sizeOptions, id: \.self) { size in
                                    Text("\(size) 阶").tag(size)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                    Section("最近") {
                        ForEach(records) { record in
                            SolveRow(record: record)
                        }
                        .onDelete(perform: delete)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("记录")
        .toolbar {
            if records.isEmpty == false {
                Button("清空", role: .destructive) { delete(at: IndexSet(records.indices)) }
            }
        }
    }

    private var statsRow: some View {
        HStack(alignment: .top) {
            stat("最佳", SolveStats.best(statsRecords))
            stat("平均 5", SolveStats.average(of: 5, statsRecords))
            stat("平均 12", SolveStats.average(of: 12, statsRecords))
            VStack(spacing: 4) {
                Text("\(statsRecords.count)").font(.title3.bold()).monospacedDigit()
                Text("次数").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 6)
    }

    private func stat(_ title: String, _ value: Double?) -> some View {
        VStack(spacing: 4) {
            Text(value.map(SolveStats.format) ?? "—").font(.title3.bold()).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets { context.delete(records[index]) }
        try? context.save()
    }
}

private struct SolveRow: View {
    let record: SolveRecord

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(record.effectiveSeconds.map(SolveStats.format) ?? "DNF")
                        .font(.system(.body, design: .monospaced)).bold()
                    if record.cubeSize != 3 {
                        Text("\(record.cubeSize)阶")
                            .font(.caption2.bold())
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.2), in: Capsule())
                    }
                }
                Text(record.scramble)
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(record.startedAt, style: .time)
                    .font(.caption).foregroundStyle(.secondary)
                Text("\(record.moveCount) 步")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .swipeActions {
            Button("+2") { record.penalty = .plusTwo }
            Button("DNF", role: .destructive) { record.penalty = .dnf }
        }
    }
}
