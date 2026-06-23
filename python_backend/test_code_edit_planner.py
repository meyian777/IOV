import unittest

from code_edit_planner import CodeEditPlanner


class CodeEditPlannerTest(unittest.TestCase):
    def test_parses_plain_json_plan(self):
        result = CodeEditPlanner.parse(
            '{"summary":"Renamed the method","replacement":"void start() {}"}'
        )

        self.assertEqual(result["summary"], "Renamed the method")
        self.assertEqual(result["replacement"], "void start() {}")

    def test_parses_fenced_json_plan(self):
        result = CodeEditPlanner.parse(
            '```json\n{"summary":"Done","replacement":"x = 2"}\n```'
        )

        self.assertEqual(result["replacement"], "x = 2")

    def test_rejects_invalid_plan(self):
        with self.assertRaises(ValueError):
            CodeEditPlanner.parse('{"summary":"Missing replacement"}')
