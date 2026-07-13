import unittest

from command_interpreter import CommandInterpreter


class CommandInterpreterTest(unittest.TestCase):
    def test_interprets_spanish_command_without_executing_it(self):
        result = CommandInterpreter.interpret(
            "OSvoz, abre Visual Studio Code"
        ).to_dict()

        self.assertEqual(result["intent"], "open_vscode")
        self.assertEqual(result["action"], "OPEN_VSCODE")
        self.assertFalse(result["requires_confirmation"])
        self.assertFalse(result["executable"])

    def test_interprets_basic_commands_without_wake_word(self):
        terminal = CommandInterpreter.interpret("abre terminal")
        terminal_with_article = CommandInterpreter.interpret("abre la terminal")
        active_project = CommandInterpreter.interpret("qué proyecto está activo")
        active_project_variant = CommandInterpreter.interpret(
            "qué proyecto es activo"
        )

        self.assertEqual(terminal.intent, "open_terminal")
        self.assertEqual(terminal.action, "OPEN_TERMINAL")
        self.assertFalse(terminal.requires_confirmation)
        self.assertEqual(terminal_with_article.intent, "open_terminal")
        self.assertEqual(terminal_with_article.action, "OPEN_TERMINAL")
        self.assertFalse(terminal_with_article.requires_confirmation)
        self.assertEqual(active_project.intent, "inspect_project")
        self.assertEqual(active_project_variant.intent, "inspect_project")

    def test_unknown_phrase_remains_conversation(self):
        result = CommandInterpreter.interpret(
            "OSvoz explícame qué es una función"
        )

        self.assertEqual(result.intent, "conversation")
        self.assertIsNone(result.action)

    def test_interprets_python_execution_without_executing_it(self):
        result = CommandInterpreter.interpret(
            "OSvoz ejecuta script Python"
        )

        self.assertEqual(result.intent, "run_python_script")
        self.assertEqual(result.action, "RUN_PYTHON_SCRIPT")
        self.assertTrue(result.requires_confirmation)
        self.assertFalse(result.executable)
