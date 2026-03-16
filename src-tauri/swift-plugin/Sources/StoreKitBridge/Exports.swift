import Foundation

// Helper to run async code from sync C entry points
private func runAsync<T>(_ block: @escaping () async -> T) -> T {
    let semaphore = DispatchSemaphore(value: 0)
    var result: T!
    Task {
        result = await block()
        semaphore.signal()
    }
    semaphore.wait()
    return result
}

private func allocateCString(_ string: String) -> UnsafeMutablePointer<CChar> {
    let utf8 = string.utf8CString
    let count = utf8.count
    let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: count)
    let mutableBuffer = UnsafeMutableBufferPointer(start: buffer, count: count)
    _ = mutableBuffer.initialize(from: utf8)
    return buffer
}

// MARK: - C-callable exports

@_cdecl("storekit_fetch_products")
public func storekitFetchProducts() -> UnsafeMutablePointer<CChar> {
    if #available(macOS 13.0, *) {
        let json = runAsync { await StoreKitManager.shared.fetchProducts() }
        return allocateCString(json)
    }
    return allocateCString("{\"ok\":false,\"error\":\"macOS 13+ required\"}")
}

@_cdecl("storekit_purchase")
public func storekitPurchase(_ productId: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar> {
    let id = String(cString: productId)
    if #available(macOS 13.0, *) {
        let json = runAsync { await StoreKitManager.shared.purchase(productId: id) }
        return allocateCString(json)
    }
    return allocateCString("{\"ok\":false,\"error\":\"macOS 13+ required\"}")
}

@_cdecl("storekit_check_entitlements")
public func storekitCheckEntitlements() -> UnsafeMutablePointer<CChar> {
    if #available(macOS 13.0, *) {
        let json = runAsync { await StoreKitManager.shared.checkEntitlements() }
        return allocateCString(json)
    }
    return allocateCString("{\"ok\":false,\"error\":\"macOS 13+ required\"}")
}

@_cdecl("storekit_restore_purchases")
public func storekitRestorePurchases() -> UnsafeMutablePointer<CChar> {
    if #available(macOS 13.0, *) {
        let json = runAsync { await StoreKitManager.shared.restorePurchases() }
        return allocateCString(json)
    }
    return allocateCString("{\"ok\":false,\"error\":\"macOS 13+ required\"}")
}

@_cdecl("storekit_free_string")
public func storekitFreeString(_ ptr: UnsafeMutablePointer<CChar>) {
    ptr.deallocate()
}
