import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:collection/collection.dart';

class Prompt{
  DeepCollectionEquality mapEquality = const DeepCollectionEquality();
  Map appInfo = {};
  String ghUrl = "";

  Prompt._internal(this.ghUrl,);
  factory Prompt({required String ghUrl}){
    return Prompt._internal(ghUrl);
  }

  Future<Map> getAppData() async {
    final info = await PackageInfo.fromPlatform();
    final output = {
      "version": info.version,
      "name": info.appName
    };
    return output;
  }

  initialize() async {
    appInfo = await getAppData();
  }

  Future<String> generate(
    String userprompt,
    List chatlog,
    Map modelInfo, {
    bool addTime = false,
    bool shareLocale = false,
    String currentLocale = "en",
    bool ignoreInstructions = false,
    bool ignoreContext = false,
  }) async {
    // Used only for title generation — skip everything
    if (ignoreContext) return "";

    // ignoreInstructions: bare conversation wrapper only (no system prompt)
    if (ignoreInstructions) {
      if (chatlog.isEmpty) return "";
      String bare = "You are having a conversation with the User.\n"
          "Don't prepend \"Gemini\" or a timestamp before your answer. Only reply with your answer.\n\n"
          "### [CHAT HISTORY]";
      for (var line in chatlog) {
        bare += "\n - ${line["user"]} (${DateFormat('dd/MM/yyyy, HH:mm').format(DateTime.fromMillisecondsSinceEpoch(int.parse(line["time"])))}) : ${line["message"]}";
      }
      return bare;
    }

    // ── 1. System instructions block ─────────────────────────────────────────
    String output = "## [SYSTEM INSTRUCTIONS]\n$userprompt";

    // Replace static values that may appear in any prompt (e.g. system_default.md)
    output = output
        .replaceAll("%modelversion%", modelInfo["version"] ?? "Unknown")
        .replaceAll("%devname%", "Puzzak")
        .replaceAll("%appname%", appInfo["name"] ?? "PAIOS")
        .replaceAll("%appversion%", appInfo["version"] ?? "")
        .replaceAll("%ghrepolink%", ghUrl);

    // Strip any leftover legacy placeholders so they don't confuse the model
    output = output.replaceAll(RegExp(r'%\w+%'), '');


    if (addTime || shareLocale) {
      String contextData = "\n\n### [CONTEXTUAL DATA]";
      if (addTime) {
        contextData += "\n - Current Time: ${DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now())}";
      }
      if (shareLocale) {
        contextData += "\n - Language: $currentLocale";
      }
      output += contextData;
    }

    // ── 4. Data & instruction rules ───────────────────────────────────────────
    List<String> rules = [];
    if (shareLocale) {
      rules.add("You MUST respond ONLY in the $currentLocale language unless the user asks you to switch.");
    }
    if (addTime) {
      rules.add("You MUST use the \"Current Time\" from [CONTEXTUAL DATA] as your knowledge of the current date and time. Do not volunteer the time unless the user asks.");
      rules.add("You MUST NOT use Current Time as the date for factual or historical questions.");
      rules.add("Current Time is only for direct user convenience, e.g. telling the time or answering \"how long ago was...?\".");
    }
    if (rules.isNotEmpty) {
      output += "\n\n## [DATA & INSTRUCTION RULES]";
      for (var rule in rules) {
        output += "\n - $rule";
      }
    }

    // ── 5. Chat history ───────────────────────────────────────────────────────
    if (chatlog.isNotEmpty) {
      output += "\n\n### [CHAT HISTORY]"
          "\n - Do NOT quote the \"User:\" or \"Gemini:\" markers — they are context markers for you only."
          "\n - Focus on the user's LATEST message, using the history only for context.";
      for (var line in chatlog) {
        output += "\n - ${line["user"]} (${DateFormat('dd/MM/yyyy, HH:mm').format(DateTime.fromMillisecondsSinceEpoch(int.parse(line["time"])))}) : ${line["message"]}";
      }
    }

    return output;
  }

  /// Builds a system prompt for silent continuation of a truncated response.
  ///
  /// There is NO user turn — the model gets a [CONTINUATION] system directive
  /// with the original question AND the partial text it already wrote, so it
  /// can tell when its answer is semantically complete and stop on its own.
  Future<String> generateContinuation(
    String userprompt,
    Map modelInfo,
    String partialText,
    String originalQuestion, {
    bool addTime = false,
    bool shareLocale = false,
    String currentLocale = "en",
  }) async {
    // Same system persona
    String output = "## [SYSTEM INSTRUCTIONS]\n$userprompt";
    output = output
        .replaceAll("%modelversion%", modelInfo["version"] ?? "Unknown")
        .replaceAll("%devname%", "Puzzak")
        .replaceAll("%appname%", appInfo["name"] ?? "PAIOS")
        .replaceAll("%appversion%", appInfo["version"] ?? "")
        .replaceAll("%ghrepolink%", ghUrl);
    output = output.replaceAll(RegExp(r'%\w+%'), '');

    if (addTime || shareLocale) {
      String contextData = "\n\n### [CONTEXTUAL DATA]";
      if (addTime) {
        contextData += "\n - Current Time: ${DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now())}";
      }
      if (shareLocale) {
        contextData += "\n - Language: $currentLocale";
      }
      output += contextData;
    }

    List<String> rules = [];
    if (shareLocale) {
      rules.add("You MUST respond ONLY in the $currentLocale language unless the user asks you to switch.");
    }
    if (addTime) {
      rules.add("You MUST use the \"Current Time\" from [CONTEXTUAL DATA] as your knowledge of the current date and time. Do not volunteer the time unless the user asks.");
    }
    if (rules.isNotEmpty) {
      output += "\n\n## [DATA & INSTRUCTION RULES]";
      for (var rule in rules) {
        output += "\n - $rule";
      }
    }

    // System-level continuation — includes the original question so the model
    // knows WHAT it's answering and can recognise when the answer is complete.
    output += "\n\n## [CONTINUATION]\n"
        "The user's original question was: \"$originalQuestion\"\n"
        "Your response was interrupted by a system timeout before you finished answering it.\n"
        "Rules:\n"
        " - Output ONLY the direct continuation of the partial text below.\n"
        " - Do NOT restart, summarise, or repeat content already in the partial text.\n"
        " - Do NOT add any preamble, greeting, or acknowledgment.\n"
        " - Pick up EXACTLY where the partial text ends — continue mid-sentence if necessary.\n"
        " - Once your answer to the original question is complete, STOP. Do not pad or extend.\n"
        "--- PARTIAL TEXT (continue from here) ---\n"
        "$partialText\n"
        "--- END OF PARTIAL TEXT ---";

    return output;
  }
}