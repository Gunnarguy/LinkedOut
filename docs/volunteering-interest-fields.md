# Volunteering Interest Fields

Field Name                        Sub-Field      Required   Description
                                   Name

 supportedNonprofits                              No         DEPRECATED. Use
                                                             "selectedContactInterests" instead.
                                                             Optional array of
                                                             SupportedNonprofit.

                                   companyId      No         A standardized referenced
                                                             company URN. Refer here for more
                                                             information.

                                   companyName    Yes        Localizable company name. It is a
                                                             MultiLocaleString object type.

 supportedPredefinedCauses                        No         An array of enum. Enum of
                                                             predefined volunteering causes:
                                                                   animalRights
                                                                   artsAndCulture
                                                                   children
                                                                   civilRights
                                                                   economicEmpowerment
                                                                   education
                                                                   environment
                                                                   health
                                                                   humanRights
                                                                   humanitarianRelief
                                                                   politics
                                                                   povertyAlleviation
                                                                   scienceAndTechnology
                                                                   socialServices


 supportedUserDefinedCauses                       No         An array of user inputted string.
                                                             Not currently used in any LinkedIn
                                                             platform's UI.
