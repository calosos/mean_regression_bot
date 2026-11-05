"""Validate extraction: test code must execute the intended production bodies."""
import unittest

from test.harness import cpp_arrays, declaration, function, structure


class HarnessTests(unittest.TestCase):
    def test_function_ignores_braces_inside_comments_and_strings(self):
        text = '''void TargetFunction()
{
   string text="a } brace and // text";
   // a misleading }
   /* { another } comment */
   if(true) { Print(text); }
}
void Other() { return; }
'''
        extracted = function(text, "TargetFunction")
        self.assertTrue(extracted.endswith('if(true) { Print(text); }\n}'))
        self.assertNotIn("void Other", extracted)

    def test_missing_function_fails_instead_of_using_a_stale_copy(self):
        with self.assertRaisesRegex(ValueError, "not found"):
            function("void Other() {}", "Missing")

    def test_struct_and_global_extraction_excludes_other_code(self):
        text = 'struct Data { ulong ids[]; };\nData g_data[];\nvoid Other() {}'
        self.assertEqual(structure(text, "Data"), 'struct Data { ulong ids[]; };')
        self.assertEqual(declaration(text, "g_data"), 'Data g_data[];')

    def test_array_adapter_preserves_grouped_declarations_and_logic(self):
        actual = cpp_arrays('double incoming[],outgoing[];\nulong ids[];\nif(incoming[i]>0) outgoing[i]+=v;')
        self.assertEqual(actual, 'std::vector<double> incoming,outgoing;\nstd::vector<ulong> ids;\nif(incoming[i]>0) outgoing[i]+=v;')


if __name__ == "__main__":
    unittest.main()
