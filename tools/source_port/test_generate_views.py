import hashlib,unittest
from generate_views import transform,RULES
class ViewAdapterTests(unittest.TestCase):
    def test_rules_preserve_unrelated_source_and_validate_exact_counts(self):
        for name,(_,old,new,count,_) in RULES.items():
            source=('// own fixture\n'+('\n'.join([old]*count))+'\n// static callbacks preserved\n').encode()
            text,report=transform(name,source,hashlib.sha256(source).hexdigest())
            self.assertEqual(text.count(new),count);self.assertTrue(text.endswith('// static callbacks preserved\n'))
            self.assertEqual(report['replacementCount'],count);self.assertIn(old.encode(),source)
    def test_wrong_hash_is_rejected(self):
        with self.assertRaisesRegex(ValueError,'hash mismatch'):transform('Bard.cs',b'owned fixture','0'*64)
    def test_changed_source_shape_fails_closed_even_with_new_pin(self):
        data=b'changed target'
        with self.assertRaisesRegex(ValueError,'pattern drift'):transform('Bard.cs',data,hashlib.sha256(data).hexdigest())
    def test_unknown_rule_is_rejected(self):
        with self.assertRaisesRegex(ValueError,'Unknown'):transform('Unreviewed.cs',b'','')
if __name__=='__main__':unittest.main()
