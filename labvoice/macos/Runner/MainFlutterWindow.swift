import Cocoa
import AVFoundation
import FlutterMacOS
import LocalAuthentication
import Speech

private final class ControlSpeechStreamHandler: NSObject, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?
  private let audioEngine = AVAudioEngine()
  private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
  private var recognitionTask: SFSpeechRecognitionTask?
  private var recognizer: SFSpeechRecognizer?
  private var running = false
  private var tapInstalled = false

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    stop()
    return nil
  }

  func start(locale: String, completion: @escaping (Result<Bool, Error>) -> Void) {
    stop()
    SFSpeechRecognizer.requestAuthorization { [weak self] status in
      guard let self else { return }
      guard status == .authorized else {
        DispatchQueue.main.async {
          completion(.failure(NSError(
            domain: "IOVControlSpeech",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Speech recognition is not authorized."]
          )))
        }
        return
      }
      DispatchQueue.main.async {
        do {
          try self.beginRecognition(locale: locale)
          completion(.success(true))
        } catch {
          completion(.failure(error))
        }
      }
    }
  }

  func stop() {
    if audioEngine.isRunning {
      audioEngine.stop()
    }
    if tapInstalled {
      audioEngine.inputNode.removeTap(onBus: 0)
      tapInstalled = false
    }
    recognitionRequest?.endAudio()
    recognitionTask?.cancel()
    recognitionTask = nil
    recognitionRequest = nil
    running = false
  }

  private func beginRecognition(locale: String) throws {
    let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale))
    guard let recognizer, recognizer.isAvailable else {
      throw NSError(
        domain: "IOVControlSpeech",
        code: 2,
        userInfo: [NSLocalizedDescriptionKey: "The local speech recognizer is unavailable."]
      )
    }
    self.recognizer = recognizer
    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true
    request.taskHint = .confirmation
    request.contextualStrings = [
      "IOV pausa", "IOV continúa", "IOV detente",
      "IOV pause", "IOV continue", "IOV stop",
    ]
    recognitionRequest = request

    let inputNode = audioEngine.inputNode
    do {
      try inputNode.setVoiceProcessingEnabled(true)
    } catch {
      // Some microphones do not expose Apple's echo-cancelled voice mode.
      // Recognition can still continue with their normal input format.
    }
    let format = inputNode.outputFormat(forBus: 0)
    guard format.sampleRate > 0 && format.channelCount > 0 else {
      throw NSError(
        domain: "IOVControlSpeech",
        code: 3,
        userInfo: [NSLocalizedDescriptionKey: "The microphone input format is invalid."]
      )
    }
    inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
      request?.append(buffer)
    }
    tapInstalled = true

    recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
      guard let self else { return }
      if let result {
        let measuredConfidence = result.bestTranscription.segments.last?.confidence ?? -1
        let confidence = measuredConfidence > 0 ? measuredConfidence : -1
        DispatchQueue.main.async {
          self.eventSink?([
            "type": "transcript",
            "transcript": result.bestTranscription.formattedString,
            "confidence": confidence,
            "final": result.isFinal,
          ])
        }
      }
      if let error {
        DispatchQueue.main.async {
          self.eventSink?([
            "type": "error",
            "message": error.localizedDescription,
          ])
          self.stop()
        }
      } else if result?.isFinal == true {
        DispatchQueue.main.async {
          self.stop()
        }
      }
    }
    audioEngine.prepare()
    try audioEngine.start()
    running = true
    DispatchQueue.main.async {
      self.eventSink?(["type": "status", "status": "listening"])
    }
  }
}

class MainFlutterWindow: NSWindow {
  private var controlSpeechHandler: ControlSpeechStreamHandler?
  private var controlSpeechChannel: FlutterMethodChannel?
  private var controlSpeechEvents: FlutterEventChannel?

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

    let controlHandler = ControlSpeechStreamHandler()
    let controlEvents = FlutterEventChannel(
      name: "osvoz/control_speech/events",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    controlEvents.setStreamHandler(controlHandler)
    let controlChannel = FlutterMethodChannel(
      name: "osvoz/control_speech",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    controlChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "start":
        let arguments = call.arguments as? [String: Any]
        let locale = arguments?["locale"] as? String ?? "es_ES"
        controlHandler.start(locale: locale) { outcome in
          switch outcome {
          case .success(let started):
            result(started)
          case .failure(let error):
            result(FlutterError(
              code: "control_speech_unavailable",
              message: error.localizedDescription,
              details: nil
            ))
          }
        }
      case "stop":
        controlHandler.stop()
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    controlSpeechHandler = controlHandler
    controlSpeechEvents = controlEvents
    controlSpeechChannel = controlChannel

    super.awakeFromNib()
  }
}
