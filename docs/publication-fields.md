# Publication Fields

Field         Sub-Field    Required   Description
 Name          Name

 id                         Yes        The unique identifier of the publication object.

 authors                    Yes        People who wrote the publication or contributed to it.
                                       Represented in an array of Contributors. Required to have
                                       the member's own person URN in the array.

               memberId     No         The contributor represented in person URN.

               name         No         Localizable member name. It is a MultiLocaleString type.

 date                       No         Day, month, and year indicating when the publication was
                                       published. It is a Date type.

 description                No         Localizable description of the publication. It is a
                                       MultiLocaleRichText type.

 name                       Yes        Localizable name of the publication. It is a
                                       MultiLocaleString type.

 publisher                  No         Localizable publication or publisher for the title. It is a
                                       MultiLocaleString type.

 url                        No         URL referencing the publication represented in string.
