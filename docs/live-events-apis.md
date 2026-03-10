# Live Events APIs

Overview
Use the Live Events API to stream and manage Live Events with your LinkedIn network.
The Live Events API offers the following functionality:

   1. Register the Live Event.
   2. Ingest RTMP(s) content.
   3. Create a Post to share your Live Event with your LinkedIn network.
   4. End the Live Event.
   5. Check the Live Event status.




Getting Started

Authenticating Members
New members authenticating with your developer application for the first time will need
to follow the Authenticating with OAuth 2.0 Guide. When requesting an authorization
code in Step 2 of the OAuth 2.0 Guide, make sure to request the minimum set of
permission scopes required for your use case.


  ７ Note

  Before authenticating with OAuth 2.0, determine if your use case permits creating
  live events for the member, or a company page. Combining both member and
  company page permission scopes within a single authentication request is not
  permitted.



  ７ Note

  LinkedIn Live is currently a beta feature. As a broadcaster, to apply for access see
  Applying for Live Events Broadcasting .




Member Live Events
 Permission      Description
 Name

 r_member_live   READ access to a member's live events. This permission scope allows you to
                 check the status of your Live Event, as well as retrieve the Live Event playable
                 streams.

 w_member_live   WRITE access to a member's live events. This permission scope allows you to
                 upload and manage your Live Event.

 r_liteprofile   READ access to a member's lite profile. This permission scope permits access to
                 retrieve the user's ID via the Profile API.




Company Page Live Events

 Permission Name         Description

 r_organization_live     READ access to your organization's live events. This permission scope
                         allows you to check the status of your Live Event, as well as retrieve the
                         Live Event playable streams.

 w_organization_live     WRITE access to your organization's live evends. This permission scope
                         allows you to upload and manage your Live Events.

 r_organization_admin    READ access to a member's organization or company page. This
                         permission scope permits access to retrieve the organization ID via the
                         Organization Access Control API.



Tiering
The Live Events API Program is available in two tiers: Development and Standard Tiers.
The intent of the Development Tier is to introduce Developers to Live Events APIs, giving
you limited access to create and view Live Events on LinkedIn. A prerequisite to
requesting access to the Standard Tier will require a demonstration from your platform,
showcasing each of the Live Events certification test cases. Access to both the
Development and Standard Tiers are available through managing your developer
applications Products at developer.linkedin.com .


Development Tier

The Developement Tier contains access to all APIs and services of the full Standard Tier,
with a restriction on the total number of API calls your developer application can
request within a 24 hour period. Generally, each Live Events API is limited to 100 API
requests per day -- giving you the freedom to test and develop against LinkedIn APIs for
your developer application. The intent of the Development Tier is to give you a preview
of the Live Events Program, and to demonstrate your proficiency in integrating with
LinkedIn before being elevated to the Standard Tier.


Standard Tier
When you are ready to launch your LinkedIn Live Events integration to your
broadcasters, you must request access to the Standard Tier. We will take this time to
review your integration with LinkedIn, and require a demostration video showcasing
your fulfillment of our Certification Test Cases.



Register
Register your Live Event using the liveAssetActions API with the action query
parameter to register .


  ７ Note

  Newly registered Live Events will be discarded if ingestion has not started within 1
  hour. After ingestion has started, a timeout will occur if the ingest URL has not
  received any data within 120 seconds.



 Field Name                Type           Description

 owner                     Person or      The unique identifier of the member or organization
                           Organization   registering the asset. To identify your Person URN, use
                           URN            the Lite Profile API and append the ID returned to
                                          "urn:li:person:".
                                          To identify your Organization URN, use the
                                          Organization Access Control API. You must be the
                                          Administrator of your Organization in order to post to
                                          your Organization Page.

 recipes                   AssetRecipe    Defines the asset media type. The live event asset
                                          media type is always
                                          urn:li:digitalmediaRecipe:feedshare-live-video.
Field Name               Type         Description

region                   string       The region specifies the closest region your asset
                                      should be registered to. Possible values include:
                                      1. WEST_US (West US)
                                      2. EAST_US_NORTH (Northeastern US)
                                      3. EAST_US_SOUTH (Southeastern US)
                                      4. CENTRAL_US (Central US)
                                      5. SOUTH_CENTRAL_US (South Central US)
                                      6. SOUTH_AMERICA (South America)
                                      7. NORTH_EUROPE (North Europe)
                                      8. WEST_EUROPE (West Europe)

autoCaptionLanguageTag   string       The BCP-47 language tag of the auto captions to
                         (optional)   generated for the live event. Use "en-US" for English.
                                      Remove this parameter if you do not want auto
                                      captions added.



  Tip

 Use decoration syntax to retrieve the Person ID within a single request. GET
 https://api.linkedin.com/v2/me?projection=(id )



  Tip

 Use decoration syntax to retrieve the Organization URN within a single request.
 https://api.linkedin.com/v2/organizationAcls?q=roleAssignee&projection=
 (elements*(organization~))



API Request
 HTTP


 POST https://api.linkedin.com/v2/liveAssetActions?action=register




Sample Request Body
 JSON


 {
        "registerLiveEventRequest": {
            "owner": "urn:li:person:12345",
             "recipes": ["urn:li:digitalmediaRecipe:feedshare-live-video"],
             "region": "WEST_US"
         }
  }



A successful response will include an array of ingestUrls where RTMPS is the preferred
ingestion protocol. Secondary ingest URLs are available in the event the primary ingest
URL is unavailable.

Ingestion needs to begin before creating your Post on LinkedIn.

The asset ID will be used in subsequent requests to create a Post, end the Live Event.



Sample Response Body
  JSON


  {
      "value": {
          "ingestUrls": [
              {
                  "ingestProtocol": "RTMP",
                  "url":
  "rtmp://12345.channel.media.azure.net:1935/live/12345"
              },
              {
                  "ingestProtocol": "RTMP",
                  "url":
  "rtmp://12345.channel.media.azure.net:1936/live/12345"
              },
              {
                  "ingestProtocol": "RTMPS",
                  "url":
  "rtmps://12345.channel.media.azure.net:2935/live/12345"
              },
              {
                  "ingestProtocol": "RTMPS",
                  "url":
  "rtmps://12345.channel.media.azure.net:2936/live/12345"
              }
          ],
          "previewUrls": [
              "https://12345-vectoreimedia2.preview-
  usw22.channel.media.azure.net/e57e889f-aaaa-bbbb-cccc-
  c337afacf31a/preview.ism/manifest"
          ],
          "mediaArtifact": "urn:li:digitalmediaMediaArtifact:
  (urn:li:digitalmediaAsset:12345,urn:li:digitalmediaMediaArtifactClass:feedsh
  are-live-liveinput)",
          "asset": "urn:li:digitalmediaAsset:12345"
       }
  }




  ７ Note

  We recommend using RTMPS whenever available. If you would like to take
  advantage of a backup stream, a separate time-synced hardware encoder can be
  used to stream to the secondary RTMP(s) urls provided.




Live Ingest Requirements
Use the following specifications when encoding your Live Event:

 Field Name        Description

 Duration          max 4 hours. Live Events may not exceed 4 hour limit.

 Aspect Ratio      16:9

 Resolution        max 1080p

 Frame Rate        max 30 fps

 Key Frame         every 2 seconds (60 frames)

 Bitrate           max 6 mbps video; max 128 kbps audio, 48 khz sample rate

 Encoding          H264 video, AAC audio

 Protocol          RTMP/RTMPS (preferred)



  ７ Note

  When streaming via RTMP, check firewall and/or proxy settings to confirm that
  outbound TCP ports 1935 and 1936 are open. When streaming via RTMPS, check
  firewall and/or proxy settings to confirm that outbound TCP ports 2935 and 2936
  are open. For a complete list of IP ranges required for allowlisting, please refer to
  Microsoft Azure IP Ranges       .




Ingest and Create a User Generated Content
(UGC) Post
Using the RTMP or RTMPS ingest URLs from the previous step, you may now begin
ingestion of your Live Event.

Before creating the Post, first check if the Live ViEventdeo is ready to be shared on
LinkedIn.



Check Recipe Status
To check the status of your Live Event, send a GET request to the assets API. After
successful ingestion, the recipe status is AVAILABLE , and ready to be included with your
UGCPost.


  ７ Note

  If your asset recipe status has not updated after 15 seconds, there may be an issue
  with ingestion. End the current session by sending the action to endLiveEvent, and
  try again by registering a new Live Event.



 Recipe        Description
 Status

 NEW           A newly assigned recipe. This status is only used for new assignments. Transitions
               to PROCESSING as soon as processing requests are sent.

 PROCESSING    Some or all of the recipe's required artifacts are not available and processing is
               underway to generate the missing artifacts.

 AVAILABLE     All of the recipe's required artifacts are available.

 INCOMPLETE    The artifact is not available because it has been deleted or is in deleting process.



API Request
  HTTP


  GET https://api.linkedin.com/v2/assets/:id




Sample API Response
  JSON
  {
         "owner": "urn:li:person:12345",
         "resourceRelationships": [],
         "serviceRelationships": [],
         "recipes": [
             {
                 "recipe": "urn:li:digitalmediaRecipe:feedshare-live-video",
                 "status": "AVAILABLE"
             }
         ],
         "mediaTypeFamily": "VIDEO",
         "created": 1539649231180,
         "executedActions": [
             {
                 "recipe": "urn:li:digitalmediaRecipe:feedshare-live-video",
                 "action": "PROCESSING",
                 "createdAt": 1539649231234
             },
             {
                 "recipe": "urn:li:digitalmediaRecipe:feedshare-live-video",
                 "action": "PROCESSED",
                 "createdAt": 1539649504293
             }
         ],
         "lastModified": 1539649504293,
         "id": "12345",
         "status": "ALLOWED"
  }



Use the ugcPosts API to create a Post on LinkedIn, viewable by your LinkedIn network.
Include the asset ID returned from registering the Live Event, as well as relevant Post
metadata in the request body. Keep in mind that the UGC Post must be created as soon
as you begin ingestion.


API Request
  HTTP


  POST https://api.linkedin.com/v2/ugcPosts




  ７ Note

  All requests require the following header: X-Restli-Protocol-Version: 2.0.0




Request Body Schema
Field Name            Description                                   Format                        Required

author                The author of a share contains either         Person URN                    Yes
                      the Person or Organization URN.               Organization URN

lifecycleState        Defines the state of the share. For the       string                        Yes
                      purposes of creating a share, the
                      lifecycleState will always be PUBLISHED .

specificContent       Provides additional options while             ShareContent                  Yes
                      defining the content of the share.

visibility            Defines any visibility restrictions for the   MemberNetworkVisibility       Yes
                      share. Possible values include:
                             PUBLIC - The share will be
                             viewable by anyone on LinkedIn.




Share Content

Field Name                  Description                                            Format         Required

shareCommentary             Provides the primary content for the share.            string         Yes

shareMediaCategory          Represents the media assets attached to the            string         Yes
                            share. Possible values include:
                                   LIVE_VIDEO - The share contains live
                                   event content.


media                       Use the Asset URN returned from registering            ShareMedia[]   No
                            the live event.




Share Media

Field        Description                                                     Format               Required
Name

status       Must be configured to READY .                                   string               Yes

media        ID of the uploaded image asset. If you are uploading            DigitalMediaAsset    No
             an article, this field is not required.                         URN



Request Headers

Header                                                                       Value
 Header                                                      Value

 X-RestLi-Method                                             Create



Sample Request Body
  JSON


  {
         "author": "urn:li:person:abcde12345",
         "lifecycleState": "PUBLISHED",
         "specificContent": {
             "com.linkedin.ugc.ShareContent": {
                 "media": [
                     {
                         "media": "urn:li:digitalmediaAsset:12345",
                         "status": "READY"
                     }
                 ],
                 "shareCommentary": {
                     "attributes": [],
                     "text": "Join us as we live stream!"
                 },
                 "shareMediaCategory": "LIVE_VIDEO"
             }
         },
         "visibility": {
             "com.linkedin.ugc.MemberNetworkVisibility": "PUBLIC"
         }
  }



A 201 response confirms your UGC Post has been created successfully. To generate a
user-friendly URL to your newly created UGC Post, identify the X-RestLi-Id within the
response header. Append the header value to https://linkedin.com/feed/update/ . The
resulting URL should resemble:

  HTTP


  https://www.linkedin.com/video/live/urn:li:ugcPost:1238957139875




End the Live Event
Once your Live Event has ended, send an action to end for your asset ID.


API Request
  HTTP


  POST https://api.linkedin.com/v2/liveAssetActions?action=end




Sample Request Body
  JSON


  {
         "asset": "urn:li:digitalmediaAsset:C5624AQEUbk4_xZgHJQ"
  }




  ７ Note

  We recommend waiting 10 seconds after your Live Event has ended before
  submitting the action to endLiveEvent to ensure your broadcast is not interrupted.


A successful response is indicated by a 200 Response Code.




Feedback
Was this page helpful?     ﾂ Yes    ﾄ No


Provide product feedback      | Get help at Microsoft Q&A
Live Events Content Access API
ﾃ    Summarize this article for me




Overview
LinkedIn Live provides a platform for individuals and organizations to broadcast live event
content to their network in real time. This video broadcasting feature is currently in beta and
available to LinkedIn Members and LinkedIn Pages that meet specific criteria. This specific
criteria is to ensure we provide access to existing content creators who have a significant
LinkedIn audience and a history of creating quality, professional video content. We also want to
ensure that video content sharing happens in a safe and trusted environment on LinkedIn.

To learn more about requesting access to LinkedIn Live, submit an application here

Already have access? Use this API to confirm whether your profile or page have been
approved. The response from this will API will determine if you have access to create live videos
using the following services: assets, liveVideos, and ugcPosts.




Content Access

API Request

 HTTP

 GET https://api.linkedin.com/v2/contentAccess/



                                                                                           ﾉ   Expand table


 Key Name          Type              Description                                                  Required

 entity:           Person URN        Used when requesting content access information on           Yes
 (member)                            behalf of a LinkedIn Member (Profile). Accepts the URL-      (Profile)
                                     encoded person urn of the member going live.

 entity:           Organization      Used when requesting content access information on           Yes
 (company)         URN               behalf of a LinkedIn Page. Accepts the URL-encoded           (Pages)
                                     organization urn.

 admin:            Person URN        Used when requesting content access information on           Yes
 (member)                            behalf of a LinkedIn Page. Accepts the URL-encoded person    (Pages)
                                     urn of the page admin going live.
 Key Name      Type          Description                                           Required

 featureType   string        Must always be the value: LIVE_VIDEO .                Yes



  ７ Note

  You must include the X-RestLi-Protocol-Version: 2.0.0 header along with your request.




Sample Request (Profile)

 HTTP

 GET https://api.linkedin.com/v2/contentAccess/(entity:
 (member:urn%3Ali%3Aperson%3AmvgmS_tF6N),featureType:LIVE_VIDEO)


In this request, we append the URL-encoded person urn to the entity:(member) parameter.

URL-decoded person urn: urn:li:person:mvgmS_tF6N URL-encoded person urn:
urn%3Ali%3Aperson%3AmvgmS_tF6N Entity: entity:(member:urn%3Ali%3Aperson%3AmvgmS_tF6N)



Sample Request (Page)

 HTTP

 GET 'https://api.linkedin.com/v2/contentAccess/(entity:
 (company:urn%3Ali%3Aorganization%3A20277203),admin:
 (member:urn%3Ali%3Aperson%3AmvgmS_tF6N),featureType:LIVE_VIDEO)


In this request, we append the URL-encoded organization urn to the entity:(company)
parameter. We also append the URL-encoded person urn to the admin:(member) parameter.

URL-decoded organization urn: urn:li:organization:20277203 URL-encoded organization urn:
urn%3Ali%3Aorganization%3A20277203 Entity: entity:

(company:urn%3Ali%3Aorganization%3A20277203)


URL-decoded person urn: urn:li:person:mvgmS_tF6N URL-encoded person urn:
urn%3Ali%3Aperson%3AmvgmS_tF6N Admin: admin:(member:urn%3Ali%3Aperson%3AmvgmS_tF6N)



API Response
If the member or page has been approved to go live, the API returns a 200 OK response.
If the member or page has not yet been approved to go live, the API returns a 404 Not Found
response.



Last updated on 05/08/2023
