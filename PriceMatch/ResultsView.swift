import SwiftUI
import SafariServices

/// Shows one big answer, up to a few store cards, and one big "Scan next item" button.
struct ResultsView: View {
    let service: PriceLookupService
    @State private var proof: ProofPage?
    @State private var showingSetup = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch service.state {
                    case .loading, .scanning:
                        loading
                    case .failed(let message):
                        failure(message)
                    case .loaded(let result):
                        answer(result)
                        product(result)
                        if !result.offers.isEmpty {
                            Text("Other stores")
                                .font(.rounded(.title3, .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                        }
                        ForEach(result.offers) { offer in
                            OfferCard(offer: offer, isBest: offer == result.cheapest) {
                                if let link = offer.link { proof = ProofPage(url: link) }
                            }
                        }
                    }
                }
                .padding(20)
            }

            BigButton(title: "Scan next item", systemImage: "barcode.viewfinder") {
                service.reset()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground))
        .sheet(item: $proof) { page in
            VStack(spacing: 0) {
                BigButton(title: "Back", systemImage: "chevron.left", style: .secondary) {
                    proof = nil
                }
                .padding(12)
                SafariView(url: page.url)
            }
            .interactiveDismissDisabled()
        }
        .sheet(isPresented: $showingSetup, onDismiss: { service.reset() }) {
            SettingsView()
        }
    }

    // MARK: - States

    private var loading: some View {
        VStack(spacing: 28) {
            ProgressView()
                .controlSize(.large)
                .scaleEffect(1.5)
                .tint(Theme.accentColor)
            Text("Looking up prices…")
                .font(.rounded(.largeTitle, .bold))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 140)
    }

    private func failure(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            Image(systemName: "exclamationmark")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(Theme.accent, in: Circle())
            Text(message)
                .font(.rounded(.title, .semibold))
            if message == LookupError.notSetUp.errorDescription || message == LookupError.badKey.errorDescription {
                BigButton(title: "Set up now", systemImage: "gearshape.fill", style: .secondary) {
                    showingSetup = true
                }
            }
        }
        .padding(.top, 60)
    }

    // MARK: - Result

    @ViewBuilder
    private func answer(_ result: LookupResult) -> some View {
        let best = result.cheapest
        let hd = result.homeDepotPrice
        let isLower = best.map { b in hd.map { b.price < $0 } ?? true } ?? false

        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: isLower ? "checkmark.seal.fill" : "equal.circle.fill")
                .font(.system(size: 34))
                .foregroundStyle(.white.opacity(0.9))

            if let best, isLower {
                Text("\(best.storeName) has it for \(Money.format(best.price))")
                    .font(.rounded(.largeTitle, .heavy))
                if let hd {
                    Text("Home Depot price: \(Money.format(hd))\nThat's \(Money.format(hd - best.price)) less")
                        .font(.rounded(.title2, .semibold))
                        .opacity(0.9)
                } else {
                    Text("Lowest price at other stores")
                        .font(.rounded(.title2, .semibold))
                        .opacity(0.9)
                }
            } else {
                Text(best == nil ? "No other stores found" : "No lower price found")
                    .font(.rounded(.largeTitle, .heavy))
                if let hd {
                    Text("Home Depot price: \(Money.format(hd))")
                        .font(.rounded(.title2, .semibold))
                        .opacity(0.9)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(answerBackground(isLower: isLower, knowsHD: hd != nil),
                    in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func answerBackground(isLower: Bool, knowsHD: Bool) -> LinearGradient {
        guard isLower else { return Theme.neutral }
        return knowsHD ? Theme.good : Theme.accent
    }

    private func product(_ result: LookupResult) -> some View {
        HStack(spacing: 14) {
            AsyncImage(url: result.product.imageURL) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Image(systemName: "shippingbox").font(.title).foregroundStyle(.secondary)
            }
            .frame(width: 64, height: 64)
            .padding(4)
            .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(result.product.title)
                    .font(.rounded(.title3, .semibold))
                    .lineLimit(2)
                Text(result.product.model.map { "Model \($0)" } ?? "Barcode \(result.barcode)")
                    .font(.rounded(.body))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct OfferCard: View {
    let offer: Offer
    let isBest: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(offer.storeName)
                        .font(.rounded(.title2, .bold))
                    Label(offer.availability, systemImage: icon)
                        .font(.rounded(.body))
                        .foregroundStyle(.secondary)
                    if let note = offer.note {
                        Text(note)
                            .font(.rounded(.body, .semibold))
                            .foregroundStyle(Color(hex: 0xF59E0B))
                    }
                }
                Spacer(minLength: 8)
                Text(Money.format(offer.price, approximate: offer.isApproximate))
                    .font(.rounded(offer.isApproximate ? .title : .largeTitle, .bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .foregroundStyle(isBest ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.primary))
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            .foregroundStyle(.primary)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .stroke(Theme.accent, lineWidth: isBest ? 3 : 0)
            )
            .opacity(offer.isEligible ? 1 : 0.7)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the store's web page")
    }

    private var icon: String {
        offer.availability.lowercased().contains("pick up") ? "storefront" : "shippingbox"
    }
}

private struct ProofPage: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
