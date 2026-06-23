import unittest

from conversation_store import ConversationStore


class ConversationStoreTest(unittest.TestCase):
    def test_keeps_recent_conversation_in_order(self):
        store = ConversationStore(max_turns=2)
        store.add("Primero", "Entendido")
        store.add("Segundo", "Continuemos")
        store.add("Tercero", "Listo")

        context = store.prompt_context()

        self.assertNotIn("Primero", context)
        self.assertIn("Segundo", context)
        self.assertIn("Tercero", context)
        self.assertLess(context.index("Segundo"), context.index("Tercero"))
