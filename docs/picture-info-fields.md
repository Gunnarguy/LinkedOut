# Picture Info Fields

This field will be deprecated on December 1, 2018. Please refer to Profile Picture fields
and Media Migration Guide for more information.


 Field Name       Sub-     Description
                  Field
                  Name

 cropInfo                  The metadata of the cropped image.

                  height   Height represented in int.

                  width    Width represented in int.

                  x        X coordinate of upper-left corner of the cropped area (upper-left
                           corner of image is 0). Represented in int.

                  y        Y coordinate of upper-left corner of the cropped area (upper-left
                           corner of image is 0). Represented in int.

 croppedImage              Profile image cropped for display.

 hidden                    Optional boolean. Defaults to false.

 masterImage               The original raw image uploaded by the member. This will not be used
                           for display and will only be used for re-cropping purposes. Only
                           available for self lookup.

 state                     Optional state defaulting to "ACTIVE". Can be the following values:
                                ACTIVE
                                 DELETED
                                 ABUSIVE
                                 QUESTIONED



Note: To get the media, replace the media-typed URN sub-string urn:li:media: to
https://media.licdn.com/mpr/mpr . For example, if the field value is

urn:li:media:/gcrc/dms/image/ABC/profile-displayphoto-shrink_800_800/0?

e=1525021200&v=alpha&t=abc123 , you can modify it to
https://media.licdn.com/mpr/mpr/gcrc/dms/image/ABC/background-profile-

shrink_800_800/0?e=1525021200&v=alpha&t=abc123 to retrieve it as a media URL via the
LinkedIn CDN.
