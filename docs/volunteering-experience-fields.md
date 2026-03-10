# Volunteering Experience Fields

Field Name        Required   Description

 id                Yes        The unique identifier of the volunteering experience object.

 cause             No         Cause of the volunteering experience represented in predefined
                              string. Enum of predefined volunteering causes:
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


 company           No         Standardized referenced company URN.

 companyName       Yes        Localizable company name. It is a MultiLocaleString type.

 description       No         Localizable description of the experience. It is a
                              MultiLocaleRichText type.

 endMonthYear      No         Month and year end date of the experience. It is a Date type. Does
                              not support "day" field.

 role              Yes        Localizable duty or responsibility performed at this volunteering
                              experience. It is a MultiLocaleString type.

 singleDate        No         A boolean that distinguishes between an ongoing volunteering
                              experience without an end date and a volunteering experience that
                              occurred at one specofic time.

 startMonthYear    No         Month and year start date of the experience. It is a Date type.
                              Does not support "day" field.
