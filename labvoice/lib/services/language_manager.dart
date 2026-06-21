class LanguageManager {
  static String currentLanguage = "en";

  static void setLanguage(String language) {
    currentLanguage = language;
  }

  static bool isEnglish() {
    return currentLanguage == "en";
  }

  static bool isSpanish() {
    return currentLanguage == "es";
  }

  static String openVSCode() {
    return "Opening Visual Studio Code, Ian.";
  }

  static String openVSCodeSuccess() {
    return "Visual Studio Code opened successfully.";
  }

  static String backendError() {
    return "I could not communicate with the Python backend.";
  }
}
