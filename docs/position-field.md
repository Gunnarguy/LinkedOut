# Position Field

Field Name            Sub-Field Name   Required   Description

 id                                     Yes        The unique identifier of the position
                                                   object.

 company                                No         Standardized referenced company
                                                   URN.

 companyName                            No         Localizable company name as
                                                   entered by the member. It is
                                                   a MultiLocaleString type.

 description                            No         Localizable description for this
                                                   position. It is a [MultiLocaleRichText]
                                                   (../object-
                                                   types.md#multilocalerichtext type.

 endMonthYear                           No         Last month and year at this position.
                                                   Missing value means the position is
                                                   current. It is a [Date](../object-
                                                   types.md#date type. Does not
                                                   support "day" field.

 location                               No         Legacy location for the position. Only
                                                   displayed if locationName field is
                                                   empty.

                       countryCode      Yes        2 letter country code. Refer to the
                                                   standardized country URNs for more
                                                   information.

                       regionCode       No         Optional integer code. Refer to the
                                                   standardized region URNs for more
                                                   information.

 locationName                           No         Legacy localizable location name of
                                                   the position. It is a MultiLocaleString
                                                   type.

 memberRichContents                     No         The list of MemberRichContentUrn
                                                   associated with the education.
                                                   Default to empty array.

 startMonthYear                         No         Start month and year at this
                                                   position. It is a Date type. Does not
                                                   support "day" field.
 Field Name                Sub-Field Name        Required   Description

 title                                           No         Localizable title name of the position.
                                                            It is a MultiLocaleString type.

 geoPositionLocation                             No         New location of the position member
                                                            worked or works at. This field is
                                                            absent if member doesn't input
                                                            position location.

                           displayLocationName   Yes        Location of the position as selected
                                                            from typeahead or entered by the
                                                            member. This field is
                                                            a MultiLocaleString type. Validations
                                                            enforced are: 1) the keys in a
                                                            localized map all exist within the
                                                            profile's supportedLocale set; 2)
                                                            there is a value for profile default
                                                            locale in the localized string maps.
