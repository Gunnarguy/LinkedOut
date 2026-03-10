# Object Types

MultiLocaleString
      MultiLocaleRichText
      MultiLocaleUrl
      Date
      LocaleString
      Locale
      Video
      Image
      Document
      Link
      AuditStamp



MultiLocaleString
The MultiLocaleString object represents a textual fields with values for multiple locales.
It contains two fields: localized and preferredLocale . See below for a detailed
description of these fields, allowed values, and sample JSON.


MultiLocaleString Schema

 Field Name        Sub-       Required   Description
                   Field
                   Name

 localized                    Yes        Maps a locale to a localized version of the string. Each
                                         key is a Locale record converted to string format, with
                                         the language, country and variant separated by
                                         underscores. Examples: 'en', 'de_DE', 'en_US_WIN',
                                         'de_POSIX', 'fr_MAC'.

 preferredLocale              No         The preferred locale to use, based on standard rules.

                   country    No         An uppercase two-letter country code as defined by
                                         ISO-3166 .

                   language   Yes        A lowercase two-letter language code as defined by
                                         ISO-639 .



Sample JSON of multiLocaleString
  JSON


  {
      "address":{
         "localized":{
            "en_US":"2029 Stierlin Ct, Mountain View, CA 94043"
         },
         "preferredLocale":{
            "country":"US",
            "language":"en"
         }
      }
  }




MultiLocaleRichText
The MultiLocaleRichText object represents a textual fields with values for multiple
locales. It contains two fields: localized and preferredLocale . See below for a detailed
description of these fields, allowed values, and sample JSON.


MultiLocaleRichText Schema

 Field Name        Sub-       Required   Description
                   Field
                   Name

 localized                    Yes        Maps a locale to a localized version of the string. Each
                                         key is a Locale record converted to string format, with
                                         the language, country and variant separated by
                                         underscores. Examples: 'en', 'de_DE', 'en_US_WIN',
                                         'de_POSIX', 'fr_MAC'.

                   rawText    No         Rich text represented in string.

 preferredLocale              No         The preferred locale to use, based on standard rules.

                   country    No         An uppercase two-letter country code as defined by
                                         ISO-3166 .

                   language   Yes        A lowercase two-letter language code as defined by
                                         ISO-639 .



Sample JSON of multiLocaleRichText
  JSON
  {
      "summary":{
         "preferredLocale":{
            "country":"US",
            "language":"en"
         },
         "localized":{
            "en_US":{
               "rawText":"Awesome summary of me."
            }
         }
      }
  }




MultiLocaleUrl
The MultiLocaleUrl object represents a textual fields with values for multiple locales. It
contains two fields: localized and preferredLocale . See below for a detailed
description of these fields, allowed values, and sample JSON.


MultiLocaleUrl Schema

 Field Name        Sub-       Required   Description
                   Field
                   Name

 localized                    Yes        Maps a locale to a localized version of the string. Each
                                         key is a Locale record converted to string format, with
                                         the language, country and variant separated by
                                         underscores. Examples: 'en', 'de_DE', 'en_US_WIN',
                                         'de_POSIX', 'fr_MAC'.

 preferredLocale              No         The preferred locale to use, based on standard rules.

                   country    No         An uppercase two-letter country code as defined by
                                         ISO-3166    .

                   language   Yes        A lowercase two-letter language code as defined by
                                         ISO-639 .



Sample JSON of multiLocaleUrl
  JSON
  {
        "url":{
           "localized":{
              "en_US":"http://www.linkedin-other.com"
           },
           "preferredLocale":{
              "country":"US",
              "language":"en"
           }
        }
  }




Date
The Date object represents a date of day, month and year.


Date Schema

 Field         Required   Type
 Name

 day           No         Day represented in integer. Valid range from 1 to 31 depending on
                          month.

 month         No         Month represented in integer. Valid range from 1 to 12.

 year          No         Year represented in integer.



Sample JSON of date
  JSON


  {
        "birthDate":{
           "day":1,
           "month":1,
           "year":1974
        }
  }




LocaleString
The LocaleString object represents a textual fields with the specified locale. It contains
two fields: locale and value . See below for a detailed description of these fields,
allowed values, and sample JSON.


LocaleString Schema

 Field    Sub-        Required   Description
 Name     Field
          Name

 locale               Yes        Maps a locale to a localized version of the string. Each key is a
                                 Locale record converted to string format, with the language,
                                 country and variant separated by underscores. Examples: 'en',
                                 'de_DE', 'en_US_WIN', 'de_POSIX', 'fr_MAC'.

          country     No         An uppercase two-letter country code as defined by ISO-3166
                                 .

          language    Yes        A lowercase two-letter language code as defined by ISO-639          .

 value                Yes        The value represented in string.



Sample JSON of LocaleString
  JSON


  {
      "name":{
         "locale":{
            "country":"US",
            "language":"en"
         },
         "value":"California"
      }
  }




Locale
The Locale object represents a country and language . See below for a detailed
description of these fields, allowed values, and sample JSON.


Locale Schema

 Field Name       Required   Description
 Field Name      Required     Description

 country         No           An uppercase two-letter country code as defined by ISO-3166       .

 language        Yes          A lowercase two-letter language code as defined by ISO-639    .



Sample JSON of Locale
  JSON


  {
         "locale":{
            "country":"US",
            "language":"en"
         }
  }




Video
The Video object represents the metadata for a video content.


Video Schema

 Field Name            Required    Format               Description

 description           Optional    MultiLocaleString    Description of this video.

 duration              Optional    int                  Duration of the video in milliseconds.

 height                Yes         int                  Height of this video in pixels.

 htmlEmbedCode         Optional    String               The html embed code for this video.

 title                 Optional    MultiLocaleString    Title of this video.

 url                   Yes         String               The external url of this video.

 width                 Yes         int                  Width of this video in pixels.



Sample JSON of Video
  JSON


  {
         "description":{
            "localized":{
               "en_US":"Description of the video"
            },
            "preferredLocale":{
               "country":"US",
               "language":"en"
            }
         },
         "duration":60000,
         "height":720,
         "title":{
            "localized":{
               "en_US":"Title of the video"
            },
            "preferredLocale":{
               "country":"US",
               "language":"en"
            }
         },
         "url":"https://linkedin.com",
         "width":1080
  }




Image
The Image object represents the metadata for an image content.



Image Schema

 Field Name         Required   Format              Description

 description        Optional   MultiLocaleString   Description of this image.

 height             Yes        int                 Height of this image in pixels.

 htmlEmbedCode      Optional   String              The html embed code for this image.

 slideShareImage    Optional   SlideShareImage     The urn to slideshow for this image if
                               Urn                 uploaded to SlideShare.

 title              Optional   MultiLocaleString   Title of this image.

 url                Yes        String              The external url of this image.

 width              Yes        int                 Width of this image in pixels.



Sample JSON of Image
  JSON


   {
         "description":{
            "localized":{
               "en_US":"Description of the image"
            },
            "preferredLocale":{
               "country":"US",
               "language":"en"
            }
         },
         "height":720,
         "title":{
            "localized":{
               "en_US":"Title of the image"
            },
            "preferredLocale":{
               "country":"US",
               "language":"en"
            }
         },
         "url":"https://linkedin.com",
         "width":1080
   }




Document
The Document object represents the metadata for a document content. The document is
in text files, e.g., .pdf, .doc, .ppt, .pps, .rtf.


Image Schema

 Field Name           Required      Format                   Description

 description          Optional      MultiLocaleString        Description of this document.

 height               Yes           int                      Height of this document in pixels.

 htmlEmbedCode        Optional      String                   The html embed code for this
                                                             document.

 slideshow            Optional      SlideShareSlideShowUrn   The urn to slideshow for this document
                                                             if uploaded to SlideShare.

 title                Optional      MultiLocaleString        Title of this document.

 url                  Yes           String                   The external url of this document.
 Field Name         Required   Format                    Description

 width              Yes        int                       Width of this document in pixels.



Sample JSON of Document
  JSON


  {
         "description":{
            "localized":{
               "en_US":"Description of the document"
            },
            "preferredLocale":{
               "country":"US",
               "language":"en"
            }
         },
         "height":720,
         "title":{
            "localized":{
               "en_US":"Title of the document"
            },
            "preferredLocale":{
               "country":"US",
               "language":"en"
            }
         },
         "url":"https://linkedin.com",
         "width":1080
  }




Link
The Link object represents the metadata for a link content. The link contains a url that
doesn not point to an image, video or document.


Link Schema

 Field Name         Required         Format                Description

 description        Optional         MultiLocaleString     Description of this link.

 title              Optional         MultiLocaleString     Title of this link.

 url                Yes              String                The external url of this link.
Sample JSON of Link
  JSON


  {
         "description":{
            "localized":{
               "en_US":"Description of the document"
            },
            "preferredLocale":{
               "country":"US",
               "language":"en"
            }
         },
         "title":{
            "localized":{
               "en_US":"Title of the document"
            },
            "preferredLocale":{
               "country":"US",
               "language":"en"
            }
         },
         "url":"https://linkedin.com"
  }




AuditStamp
The AuditStamp object represents the metadata of when an object is acted upon.


AuditStamp Schema

 Field Name      Required   Format   Description

 actor           Yes        Urn      The entity authorized the change.

 impersonator    Optional   Urn      The entity which performs the change on behalf of the
                                     actor. Must be authorized to act as the actor.

 time            Yes        long     When the event happened in epoch time.



Sample JSON of AuditStamp
  JSON


  {
         "actor":"urn:li:person:123ABC",
      "time":1332187798000
  }




CroppedImage
An image with its cropping information.


CroppedImage Schema

 Field      Required   Format      Description
 Name

 cropped    Yes        Urn         Location of the cropped image.

 original   Yes        Urn         Location of the original image.

 cropInfo   Yes        Rectangle   The cropping information defined by a rectangle in which the
                                   specified corner is the upper-left corner of the crop area.


###Sample JSON of CroppedImage

  JSON


  {
    "cropped": "urn:li:media:/gcrc/dms/image/Z561BAQF8zT9beoHupA/company-
  background_10000/0/1544648748713?
  e=1631905200&v=beta&t=ZSHOeHDliP1QEmnMoIg3GPUcLocCXMx0OaU_X2MJNks",
    "original": "urn:li:media:/gcrc/dms/image/Z561BAQF8zT9beoHupA/company-
  background_10000/0/1544648748713?
  e=1631905200&v=beta&t=ZSHOeHDliP1QEmnMoIg3GPUcLocCXMx0OaU_X2MJNks",
    "cropInfo": {
      "x": 0,
      "width": 646,
      "y": 0,
      "height": 220
    }
  }




Rectangle
An abstract rectangle defined by the coordinates of a corner and its width and height
without any associated domain specific semantics.


Rectangle Schema
 Field Name              Required         Format         Description

 height                  Yes              int            Height of the image.

 width                   Yes              int            Width of the image.

 x                       Yes              int            X coordinate of the corner.

 y                       Yes              int            Y coordinate of the corner.


###Sample JSON of Rectangle

     JSON


     {
         "x": 0,
         "width": 646,
         "y": 0,
         "height": 220
     }
