# Project Fields

Field Name        Sub-Field       Required     Description
                   Name

 id                                Yes          The unique identifier of the publication object.

 description                       No           Localizable description of the project. It is a
                                                MultiLocaleRichText type.

 endMonthYear                      No           Month and year indicating when the project ended. It
                                                is a Date type. Does not support "day" field.

 members                           Yes          People who contributed to the project. Represented in
                                                an array of Contributors. Required to have the
                                                member's own person URN in the array.

                   memberId        No           The contributor represented in person URN.

                   name            No           Localizable member name. It is a MultiLocaleString
                                                 type.

 occupation                        No           Position a member held while working on this project.
                                                Selected from a position of the member's profile.
                                                Represented as either a standardized referenced
                                                company or school URN.

 singleDate                        No           A boolean that distinguishes between an ongoing
                                                project without an end date and a project that
                                                occurred at one specofic time.

 startMonthYear                    No           Start date for the certification. It is a Date type. Does
                                                not support "day" field.

 title                             Yes          Localizable name of the project. It is a
                                                MultiLocaleString type.

 url                               No           URL referencing the project represented in string.
