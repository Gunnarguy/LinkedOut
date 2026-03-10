# Honor Fields

Field         Required     Description
 Name

 id            Yes          The unique identifier of the honor object.

 description   No           Localizable description of the honor or award. It is a
                            MultiLocaleRichText type.

 issueDate     No           Month and year the honor or award was issued. It is a Date type. Does
                            not support "day" field.

 issuer        No           Localizable entity that issued the honor or award. It is a
                            MultiLocaleString type.

 occupation    No           Member's occupation when the honor or award was completed.
                            Referenced as either a standardized referenced company or school
                            URN.

 title         Yes          Localizable title of the honor or award. It is a MultiLocaleString type.
