import unittest
from adapt_state_machines import EDITS, transform


class StateMachineAdaptationTests(unittest.TestCase):
    def test_bom_newlines_and_callback_body_are_preserved(self):
        for before, after in EDITS.values():
            data=b'\xef\xbb\xbf// own fixture\r\nvar wrapper = '+before+b';\r\nDoWork(wrapper.State);\r\n'
            result=transform(data,before,after)
            self.assertEqual(result.replace(after,before),data)
            self.assertIn(b'DoWork(wrapper.State);\r\n',result)

    def test_missing_or_duplicate_source_calls_rejected(self):
        for before, after in EDITS.values():
            with self.assertRaises(ValueError):transform(b'No call',before,after)
            with self.assertRaises(ValueError):transform(before+b'\n'+before,before,after)


if __name__=='__main__':unittest.main()
