import Foundation
import StoreKit

@available(macOS 13.0, *)
final class StoreKitManager {
    static let shared = StoreKitManager()

    let productIds = [
        "com.banyudu.token-wise.pro"
    ]

    private var products: [Product] = []
    private var updateTask: Task<Void, Never>?

    private init() {
        updateTask = Task {
            for await result in Transaction.updates {
                if case .verified(_) = result {
                    // Transaction updated — entitlement checks will pick it up
                }
            }
        }
    }

    deinit {
        updateTask?.cancel()
    }

    // MARK: - Fetch Products

    func fetchProducts() async -> String {
        do {
            products = try await Product.products(for: productIds)
            let items = products.map { product -> [String: Any] in
                [
                    "id": product.id,
                    "displayName": product.displayName,
                    "description": product.description,
                    "displayPrice": product.displayPrice,
                    "price": NSDecimalNumber(decimal: product.price).doubleValue,
                    "type": "non_consumable",
                ]
            }
            let data = try JSONSerialization.data(withJSONObject: ["ok": true, "products": items])
            return String(data: data, encoding: .utf8) ?? "{\"ok\":false,\"error\":\"encoding\"}"
        } catch {
            return "{\"ok\":false,\"error\":\"\(error.localizedDescription)\"}"
        }
    }

    // MARK: - Purchase

    func purchase(productId: String) async -> String {
        var product = products.first(where: { $0.id == productId })
        if product == nil {
            product = try? await Product.products(for: [productId]).first
        }
        guard let product = product else {
            return "{\"ok\":false,\"error\":\"Product not found\"}"
        }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    return "{\"ok\":true,\"status\":\"purchased\"}"
                case .unverified(_, let error):
                    return "{\"ok\":false,\"error\":\"Verification failed: \(error.localizedDescription)\"}"
                }
            case .userCancelled:
                return "{\"ok\":false,\"error\":\"cancelled\"}"
            case .pending:
                return "{\"ok\":true,\"status\":\"pending\"}"
            @unknown default:
                return "{\"ok\":false,\"error\":\"Unknown result\"}"
            }
        } catch {
            return "{\"ok\":false,\"error\":\"\(error.localizedDescription)\"}"
        }
    }

    // MARK: - Check Entitlements

    func checkEntitlements() async -> String {
        var hasPro = false

        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                if transaction.productID == "com.banyudu.token-wise.pro" {
                    hasPro = true
                }
            }
        }

        let dict: [String: Any] = [
            "ok": true,
            "has_pro": hasPro,
        ]

        do {
            let data = try JSONSerialization.data(withJSONObject: dict)
            return String(data: data, encoding: .utf8) ?? "{\"ok\":false,\"error\":\"encoding\"}"
        } catch {
            return "{\"ok\":false,\"error\":\"encoding\"}"
        }
    }

    // MARK: - Restore Purchases

    func restorePurchases() async -> String {
        do {
            try await AppStore.sync()
            return await checkEntitlements()
        } catch {
            return "{\"ok\":false,\"error\":\"\(error.localizedDescription)\"}"
        }
    }
}
