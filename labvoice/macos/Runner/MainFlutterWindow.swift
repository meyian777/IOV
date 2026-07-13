import Cocoa
import FlutterMacOS
import LocalAuthentication

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    let channel = FlutterMethodChannel(
      name: "osvoz/session_auth",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      let context = LAContext()
      var error: NSError?
      let reason = "Confirma tu identidad para autorizar esta acción protegida en IOV."
      if call.method == "canAuthenticate" {
        let canAuthenticate =
          context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) ||
          context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
        result(canAuthenticate)
        return
      }
      guard call.method == "authenticate" else {
        result(FlutterMethodNotImplemented)
        return
      }
      if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, _ in
          DispatchQueue.main.async {
            result(success)
          }
        }
        return
      }
      if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
          DispatchQueue.main.async {
            result(success)
          }
        }
        return
      }
      result(FlutterError(code: "auth_unavailable", message: "No local authentication method is available.", details: nil))
    }

    super.awakeFromNib()
  }
}
