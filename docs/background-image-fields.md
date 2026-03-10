# Background Image Fields

This field wae deprecated on December 1, 2018. Please refer to Background Picture
fields and Media Migration Guide for more information.


 Field Name            Sub-     Type
                       Field
                       Name

 cropInfo                       Stores the top-Y for member uploaded, repositioned images.

                       height   int

                       width    int

                       x        X coordinate of upper-left corner of the cropped area (upper-left
                                corner of image is 0). Represented in int.

                       y        Y coordinate of upper-left corner of the cropped area (upper-left
                                corner of image is 0). Represented in int.

 pictureId                      The media URN of the background image. Refer to media
                                gateway for more information.

 croppedPictureId               The media URN of the cropped background image. Refer to
                                media gateway for more information.

 customUpload                   A required representing whether the image was a member
                                upload. Always true.



  ７ Note

  Retrieving media via the LinkedIn CDN requires converting URNs to URLs as
  described in the examples below using stock photos provided by LinkedIn.

        If the media-typed URN starts with urn:li:media: , you will need to replace
        that with https://media.licdn.com/mpr/mpr . For example,
         urn:li:media:/gcrc/dms/image/ABC/background-displayphoto-

        shrink_800_800/0?e=1525021200&v=alpha&t=abc123 would translate to

         https://media.licdn.com/mpr/mpr/gcrc/dms/image/ABC/background-

        displayphoto-shrink_800_800/0?e=1525021200&v=alpha&t=abc123 .

        If the media-typed URN starts with urn:li:scds: , you will need to replace
        that with https://static.licdn.com/scds/common/u/ . For example,
        urn:li:scds:images/apps/profile/topcard_backgrounds/texture_bokeh_1400x42

        5.jpg would translate to

        https://static.licdn.com/scds/common/u/images/apps/profile/topcard_backgr

        ounds/texture_bokeh_1400x425.jpg .
