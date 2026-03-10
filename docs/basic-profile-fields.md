# Basic Profile Fields

Field Name                Description

 id                        A unique identifying value for the member. Referenced as personId in
                           other API documentation pages. Can also be referenced as an URN such
                           as urn:li:person:{personId}. This value is linked to your specific
                           application. Any attempts to use it with a different application will result
                           in a 404 error.

 firstName                 Localizable first name of the member. Represented as a MultiLocaleString
                           object type.

 localizedFirstName        Localized version of the firstName field.

 lastName                  Localizable last name of the member. Represented as a MultiLocaleString
                           object type.

 localizedLastName         Localized version of the lastName field.

 maidenName                Localizable maiden name of the member. Represented as a
                           MultiLocaleString object type.

 localizedMaidenName       Localized version of the maidenName field.

 headline                  Localizable headline of member's choosing. Represented as a
                           MultiLocaleString object type.

 localizedHeadline         Localized version of the headline field.

 profilePicture            Metadata about the member's picture in the profile. This will replace
                           pictureInfo. See Profile Picture Fields for more information.

 vanityName                The vanity name of the member. Vanity name is represented as a string is
                           used for the public profile URL: www.linkedin.com/in/{vanityName} .
