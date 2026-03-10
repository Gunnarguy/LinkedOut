# Lite Profile Fields

To access any of the Lite Profile fields listed below, your application must request the
r_liteprofile member permission scope:


 Field Name            Description

 id                    The unique identifier for the given member. May also be referenced as the
                       personId within a Person URN (urn:li:person:{personId}). The id is unique to
                       your specific developer application. Any attempts to use the id with other
                       developer applications will not succeed.

 firstName             First name of the member. Represented as a MultiLocaleString object type.

 localizedFirstName    Localized version of the firstName field.

 lastName              Last name of the member. Represented as a MultiLocaleString object type.

 localizedLastName     Localized version of the lastName field.

 profilePicture        Metadata about the member's picture in the profile. See Profile Picture
                       Fields for more information.
