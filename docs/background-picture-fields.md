# Background Picture Fields

Field Name            Description

 created               An epoch timestamp corresponding to the creation of the picture.
                       Represented in milliseconds.

 deleted               An epoch timestamp corresponding to the deletion of the picture.
                       Represented in milliseconds. Optional.

 displayImage          The digitalmediaAsset URN of the display image.

 lastModified          An epoch timestamp corresponding to the last modification of the picture.
                       Represented in milliseconds.

 originalImage         The digitalmediaAsset URN of the original image. Will only appear in self-
                       view.

 photoFilterEditInfo   Optional information object on the photo filter operations applied to the
                       background picture.


To decorate the digitalMediaAsset URN from displayImage or originalImage , you will
use parameter projection that will include ~:playableStreams . For more information,
see here about digital media asset URNs . See below for an example of Profile API:

  https


  GET https://api.linkedin.com/v2/me?projection=
  (id,backgroundPicture(displayImage~digitalmediaAsset:playableStreams))




profile api sample responses
  JSON


  {
     "backgroundPicture":{
        "displayImage":"urn:li:digitalmediaAsset:C4D03AQGsitRwG8U8ZQ",
        "displayImage~":{
           "elements":[
              {
                 "artifact":"urn:li:digitalmediaMediaArtifact:
  (urn:li:digitalmediaAsset:C4D03AQGsitRwG8U8ZQ,urn:li:digitalmediaMediaArtifa
  ctClass:profile-displayphoto-shrink_100_100)",
                 "authorizationMethod":"PUBLIC",
                 "data":{
                      "com.linkedin.digitalmedia.mediaartifact.StillImage":{
                         "storageSize":{
                            "width":100,
                            "height":100
                         },
                         "storageAspectRatio":{
                            "widthAspect":1,
                            "heightAspect":1,
                            "formatted":"1.00:1.00"
                         },
                         "mediaType":"image/jpeg",
                         "rawCodecSpec":{
                            "name":"jpeg",
                            "type":"image"
                         },
                         "displaySize":{
                            "uom":"PX",
                            "width":100,
                            "height":100
                         },
                         "displayAspectRatio":{
                            "widthAspect":1,
                            "heightAspect":1,
                            "formatted":"1.00:1.00"
                         }
                      }
                   },
                   "identifiers":[
                      {

"identifier":"https://media.licdn.com/dms/image/C4D03AQGsitRwG8U8ZQ/profile-
displayphoto-shrink_100_100/0?e=1526940000&v=alpha&t=12345",
                      "file":"urn:li:digitalmediaFile:
(urn:li:digitalmediaAsset:C4D03AQGsitRwG8U8ZQ,urn:li:digitalmediaMediaArtifa
ctClass:profile-displayphoto-shrink_100_100,0)",
                      "index":0,
                      "mediaType":"image/jpeg",
                      "identifierExpiresInSeconds":1526940000
                  }
               ]
            }
         ],
         "paging":{
            "count":10,
            "start":0,
            "links":[

               ]
           }
       }
    },
    "id":"yrZCpj2ZYQ"
}
  ７ Note

  Retrieving media via the LinkedIn CDN requires converting URNs to URLs as
  described in the examples below using stock photos provided by LinkedIn. If the
  media-typed URN starts with urn:li:media: , you will need to replace that with
  https://media.licdn.com/mpr/mpr . For example,
  urn:li:media:/gcrc/dms/image/ABC/background-displayphoto-shrink_800_800/0?

  e=1525021200&v=alpha&t=abc123 would translate to
  https://media.licdn.com/mpr/mpr/gcrc/dms/image/ABC/background-displayphoto-

  shrink_800_800/0?e=1525021200&v=alpha&t=abc123 . If the media-typed URN starts

  with urn:li:scds: , you will need to replace that with
  https://static.licdn.com/scds/common/u/ . For example,

  urn:li:scds:images/apps/profile/topcard_backgrounds/texture_bokeh_1400x425.jpg
  would translate to
  https://static.licdn.com/scds/common/u/images/apps/profile/topcard_backgrounds
  /texture_bokeh_1400x425.jpg .
