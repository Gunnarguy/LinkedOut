# Test Score Fields

Field         Required     Description
 Name

 date          No           Month and year the test was taken. It is a Date type. Does not support
                            "day" field.

 description   No           Localizable description of the test score. It is a MultiLocaleRichText
                             type.

 name          Yes          Localizable name of the test. It is a MultiLocaleString type.

 occupation    No           Position a member held while during this test. Selected from a position
                            of the member's profile. Represented as either a standardized
                            referenced company or school URN.

 score         No           Score achieved on the test represented in string.
