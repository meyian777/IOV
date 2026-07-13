import json
import re


class CodeEditPlanner:
    MAX_REPLACEMENT_CHARACTERS = 200_000

    @staticmethod
    def create(client, instruction: str, context: dict) -> dict:
        response = client.responses.create(
            model="gpt-5",
            input=[
                {
                    "role": "system",
                    "content": (
                        "You are OSvoz's code editing planner. Return only "
                        "valid JSON with exactly two string fields: summary and "
                        "replacement. replacement must contain the complete "
                        "new contents of the active file. Preserve unrelated "
                        "code and formatting. Do not use Markdown fences."
                    ),
                },
                {
                    "role": "user",
                    "content": (
                        f"Instruction: {instruction}\n"
                        f"File: {context.get('relative_file', '')}\n"
                        f"Language: {context.get('language_id', '')}\n"
                        f"Selected text:\n{context.get('selected_text', '')}\n"
                        "Current complete file:\n"
                        f"{context.get('document_text', '')}"
                    ),
                },
            ],
        )
        return CodeEditPlanner.parse(response.output_text)

    @staticmethod
    def parse(value: str) -> dict:
        text = value.strip()
        fenced = re.fullmatch(
            r"```(?:json)?\s*(.*?)\s*```",
            text,
            flags=re.DOTALL | re.IGNORECASE,
        )
        if fenced:
            text = fenced.group(1)

        decoded = json.loads(text)
        if not isinstance(decoded, dict):
            raise ValueError("The edit plan must be a JSON object.")

        summary = decoded.get("summary")
        replacement = decoded.get("replacement")
        if not isinstance(summary, str) or not summary.strip():
            raise ValueError("The edit plan is missing a summary.")
        if not isinstance(replacement, str):
            raise ValueError("The edit plan is missing replacement content.")
        if len(replacement) > CodeEditPlanner.MAX_REPLACEMENT_CHARACTERS:
            raise ValueError("The proposed replacement is too large.")

        return {
            "summary": summary.strip()[:1000],
            "replacement": replacement,
        }
