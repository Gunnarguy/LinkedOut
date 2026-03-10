# Live Events Target Audiences

With Target Audiences, you can now specify a country, region, or language along with
your Organization's Live Events posts. Target Audiences is available for use with
Company Pages only. To implement target audiences, there will be a few key changes to
your user workflow.

   1. Register the Live Event.
   2. Ingest RTMP(s) content.
   3. NEW Identify countries, regions, and languages to target. Use the geoTypeahead
        service to allow members to search for countries or regions. Refer to ISO-639           for
        a list of supported langauges.
   4. NEW Create a Post with a list of countries, regions, and languages to target to
        share your Live Event with your LinkedIn network.
   5. End the Live Event.



Geo Typeahead
The Bing Geo Typeahead API will provide a list of corresponding Geo URNs given a user
input search query. The display name represents the user-friendly representation of the
country or region, while the entity represents the URN that will be appended to the
ugcPost.


  ７ Note

  All use of the Microsoft Bing Maps location data is subject to Microsoft Bing Maps
  and MapPoint Web Service End User Terms of Use and Embedded Maps Service
  Terms of Use         and the Microsoft Privacy Statement        . By accessing any Microsoft
  Bing Maps location data, you are agreeing to be bound by these Microsoft terms.



 Field     Sub-Field        Description                                                Format

 hits                       The record containing the typeahead hit information.       Array

           displayName      Hit title. The display name of the geo URN.                String

           entity           The urn matching the search query.                         URN



API Request
 HTTP


 GET https://api.linkedin.com/v2/geoTypeahead?q=search&query=San
 GET https://api.linkedin.com/v2/geoTypeahead?q=search&query=San&locale=
 (language:en,country:US)




Parameters

Field    Sub-       Description                                                      Required
Name     Field
         Name

query               Typeahead query used to find available geo results given the     Yes
                    user input.

locale              The locale the country data is requested in, as represented by   Optional
                    the two-letter language and country codes. Defaults to en_US .

         language   A lowercase two-letter language code as defined by ISO-639 .     Optional

         country    An uppercase two-letter country code as defined by ISO-3166 .    Optional



Sample Response Body
 JSON


 {
     "paging": {
         "start": 0,
         "count": 10,
         "links": [
             {
                 "type": "application/json",
                 "rel": "next",
                 "href": "/v2/geoTypeahead?
 q=search&query=san&start=10&count=10&locale=(country:US,language:en)"
             }
         ],
         "total": 0
     },
     "elements": [
         {
             "displayText": "San Francisco Bay Area",
             "entity": "urn:li:geo:90000084"
         },
         {
             "displayText": "San Diego Metropolitan Area",
             "entity": "urn:li:geo:90010472"
         },
            {
                 "displayText": "San Antonio, Texas Metropolitan Area",
                 "entity": "urn:li:geo:90000724"
            },
            {
                 "displayText": "Santiago Metropolitan Area",
                 "entity": "urn:li:geo:90009899"
            },
            {
                 "displayText": "San Juan-Carolina Area",
                 "entity": "urn:li:geo:90009445"
            },
            {
                 "displayText": "San Luis Potosí Metropolitan Area",
                 "entity": "urn:li:geo:90010051"
            },
            {
                 "displayText": "San José Metropolitan Area",
                 "entity": "urn:li:geo:90010358"
            },
            {
                 "displayText": "Santa Barbara-Santa Maria Area",
                 "entity": "urn:li:geo:90010474"
            },
            {
                 "displayText": "San Cristóbal Metropolitan Area",
                 "entity": "urn:li:geo:90010453"
            },
            {
                 "displayText": "San Angelo Area",
                 "entity": "urn:li:geo:90000720"
            }
      ]
  }




Locales
The interfaceLocales object represents an array of Locales to target. You can specify
locales using the format below:


Schema

 Field Name      Description                                                    Required

 language        A lowercase two-letter language code as defined by ISO-639 .   Optional



Sample JSON
  JSON


  {
      "interfaceLocales": [
        {
          "language": "en"
        },
        {
          "language": "es"
        }
      ]




Audience Counts
With the Audience Counts API, you can forecast the reach of your target audience. Use
the Audience Counts API to ensure your target audience contains at least 300 followers.


Schema

 Field    Description
 Name

 active   Active audience count for the given targeting criteria. Active audience includes members
          that are more likely to visit LinkedIn sites.

 total    Total audience count for the given targeting criteria. To protect member privacy, this
          value is 0 when the audience size is less than 300. The total is a rounded approximation,
          and the degree of approximation depends upon the size of the audience segment.


The following TargetingCriteria can be used with your request. See here for more
information about Targeting Criteria.

 TargetingCriteria                               Description

 urn:li:adTargetingFacet:followedCompanies       include the Organization URN
                                                 (urn:li:organization:3487269) here

 urn:li:adTargetingFacet:interfaceLocales        include the list of Locales (urn:li:locale:en_US) here

 urn:li:adTargetingFacet:locations               include the list of Location URNs
                                                 (urn:li:geo:90000084) here


All API requests require the header: X-Restli-Protocol-Version: 2.0.0 .

To comply with Restli 2.0 format, all URNs must be URL encoded. For example,
urn:li:skill:17 is URL encoded as urn%3Ali%3Askill%3A17 .
  ７ Note

  Postman or similar API tools may not support URL encoding query parameters
  within the request. If you encounter the response: Invalid query parameters passed
  to request , please test your request using curl .




API Request
This sample submits a request to the audienceCountsV2 service to find the audience size
of Organization 5340951 under the Geo Location 90000084 and Interface Locale en_US.

  HTTP


     GET https://api.linkedin.com/v2/audienceCountsV2?
     q=targetingCriteriaV2&targetingCriteria=(include:(and:List((or:
     (urn%3Ali%3AadTargetingFacet%3AfollowedCompanies:List(urn%3Ali%3Aorganizatio
     n%3A5340951))),(or:
     (urn%3Ali%3AadTargetingFacet%3Alocations:List(urn%3Ali%3Ageo%3A90000084))),
     (or:
     (urn%3Ali%3AadTargetingFacet%3AinterfaceLocales:List(urn%3Ali%3Alocale%3Aen_
     US))))))'




Parameters

 Field Name          Required                      Type                Description

 q                   This field should always be   string              Yes
                     targetingCriteriaV2


 targetingCriteria   Yes                           targetingCriteria   Specifies the targeting criteria
                                                   object              that the member should
                                                                       match.


For reference, the unencoded and encoded Targeting Criteria used in the sample
request is provided below.


Encoded Targeting Criteria

  HTTP


     =(include:(and:List((or:
     (urn%3Ali%3AadTargetingFacet%3AfollowedCompanies:List(urn%3Ali%3Aorganizatio
     n%3A5340951))),(or:
 (urn%3Ali%3AadTargetingFacet%3Alocations:List(urn%3Ali%3Ageo%3A90000084))),
 (or:
 (urn%3Ali%3AadTargetingFacet%3AinterfaceLocales:List(urn%3Ali%3Alocale%3Aen_
 US))))))




Unencoded Targeting Criteria

 HTTP


 =(include:(and:List((or:
 (urn:li:adTargetingFacet:followedCompanies:List(urn:li:organization:5340951)
 )),(or:(urn:li:adTargetingFacet:locations:List(urn:li:geo:90000084))),(or:
 (urn:li:adTargetingFacet:interfaceLocales:List(urn:li:locale:en_US))))))




JSON Representation

 JSON


 {
     "targetingCriteria": {
       "include": {
         "and": [
           {
             "or": {
                "urn:li:adTargetingFacet:followedCompanies": [
                  "urn:li:organization:5340951"
                ]
              }
           },
           {
             "or": {
                "urn:li:adTargetingFacet:interfaceLocales": [
                  "urn:li:locale:en_US"
                ],
                "urn:li:adTargetingFacet:locations": [
                  "urn:li:geo:90000084"
                ]
              }
           }
         ]
       }
     }
 }




Sample Response

 JSON
 {
     "elements": [
       {
         "total": 420,
         "active": 0
       }
     ],
     "paging": {
       "count": 10,
       "start": 0,
       "links": []
     }
 }




ugcPosts

API Request
 HTTP


 POST https://api.linkedin.com/v2/ugcPosts




 ７ Note

 All requests require the following header: X-Restli-Protocol-Version: 2.0.0




Request Body Schema

Field Name        Description                                 Format             Required

author            The author of a share contains either       Person URN         Yes
                  the Person or Organization URN.             Organization URN

lifecycleState    Defines the state of the share. For the     string             Yes
                  purposes of creating a share, the
                  lifecycleState will always be PUBLISHED .

specificContent   Provides additional options while           ShareContent       Yes
                  defining the content of the share.
Field Name           Description                                   Format                        Required

visibility           Defines any visibility restrictions for the   MemberNetworkVisibility       Yes
                     share. Possible values include:
                            PUBLIC - The share will be
                           viewable by anyone on LinkedIn.


targetAudience       Intended audience or best fit audiences       TargetAudience                Optional
                     for this content as decided by the
                     owner.



Share Content

Field Name                 Description                                        Format             Required

shareCommentary            Provides the primary content for the share.        string             Yes

shareMediaCategory         Represents the media assets attached to the        string             Yes
                           share. Possible values include:
                                  LIVE_VIDEO - The share contains live
                                 event content.


media                      Use the Asset URN returned from registering        ShareMedia[]       No
                           the live event.



Share Media

Field        Description                                                 Format                  Required
Name

status       Must be configured to READY .                               string                  Yes

media        ID of the uploaded image asset. If you are uploading        DigitalMediaAsset       No
             an article, this field is not required.                     URN



TargetAudience

Field                Sub-Field           Description                                              Format

targetedEntities                         The entities targeted for distribution. Structured as    Array
                                         an object containing multiple arrays of targeting        of
                                         entity URNs that functions like a series of OR           Targets
                                         conditionals.                                            (see
                                                                                                  below)
Field             Sub-Field          Description                                           Format

                  geoLocations       Array of countries and regions to target. Countries   Array
                                     and regions are represented as a Geo URN.             of Geo
                                                                                           URN

                  interfaceLocales   Array of languages to target. Languages are           Array
                                     represented as a Locale.                              of
                                                                                           Locale



 ７ Note

 Your target audience must include at least 300 members.



Request Headers

Header                                                              Value

X-RestLi-Method                                                     Create



Sample Request Body
 JSON


 {
        "author":"urn:li:organization:abcde12345",
        "lifecycleState":"PUBLISHED",
        "specificContent":{
           "com.linkedin.ugc.ShareContent":{
              "media":[
                 {
                    "media":"urn:li:digitalmediaAsset:12345",
                    "status":"READY"
                 }
              ],
              "shareCommentary":{
                 "attributes":[

                 ],
                 "text":"Join us as we live stream!"
              },
              "shareMediaCategory":"LIVE_VIDEO"
           }
        },
        "visibility":{
           "com.linkedin.ugc.MemberNetworkVisibility":"PUBLIC"
        },
      "targetAudience":{
         "targetedEntities":[
            {
               "geoLocations":[
                  "urn:li:geo:867",
                  "urn:li:geo:5309"
               ],
               "interfaceLocales":[
                  {
                     "language":"en"
                  },
                  {
                     "language":"es"
                  }
               ]
            }
         ]
      }
  }



A 201 response confirms your UGC Post has been created successfully. To generate a
user-friendly URL to your newly created UGC Post, identify the X-RestLi-Id within the
response header. Append the header value to https://linkedin.com/video/live/ . The
resulting URL should resemble:

  HTTP


  https://www.linkedin.com/video/live/urn:li:ugcPost:1238957139875




Feedback
Was this page helpful?     ﾂ Yes    ﾄ No


Provide product feedback      | Get help at Microsoft Q&A
Live Events Announcements & Release
