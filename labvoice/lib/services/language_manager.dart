class LanguageManager {

  static String currentLanguage = "en";

  static void setLanguage(String language) {
    currentLanguage = language;
    print("LANGUAGE CHANGED TO: $currentLanguage");
  }

  static bool isEnglish() {
    return true;
  }

  static bool isSpanish() {
    return false;
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