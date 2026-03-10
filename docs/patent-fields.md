# Patent Fields

ﾉ      Expand table


 Field Name            Sub-Field   Required   Description
                       Name

 id                                Yes        The unique identifier of the patent object.

 applicationNumber                 No         Localizable patent application number. It is a
                                              MultiLocaleString type. Only displayed when
                                              pending is true.

 description                       No         Localizable description for additional details
                                              about this education. It is a MultiLocaleRichText
                                               type.

 filingDate                        No         Month, day, and year the patent was filed. It is a
                                              Date type. Only displayed when pending is true.

 inventors                         Yes        Members who created the patent or contributed
                                              to it. Represented in an array of Contributors.
                                              Required to have the member's own person URN
                                              in the array.

                       memberId    No         The inventor represented in person URN.

                       name        No         Localizable member name. It is a
                                              MultiLocaleString type.

 issueDate                         No         Month, day, and year the patent was officially
                                              issued. It is a Date type. Only displayed when
                                              pending is false.

 issuer                            Yes        Localizable issuer of the patent. Issuer based on
                                              country/region and is represented by lowercase
                                              two-letter country code as defined by ISO-
                                              3166 . It is a MultiLocaleString type.

 number                            No         Localizable patent number. It is a
                                              MultiLocaleString type. Only displayed when
                                              pending is false.

 pending                           Yes        The status of patent represented as a boolean.

 title                             Yes        Localizable title of the patent. It is a
                                              MultiLocaleString type.
 Field Name              Sub-Field   Required   Description
                         Name

 url                                 No         URL referencing the patent represented in string.
