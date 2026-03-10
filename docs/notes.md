# Notes

Bookmark this page to get the latest Live Events API announcements and release notes.



June 30, 2023

Update to the Available Asset Regions
After reviewing the activity for each live asset region, we have made the decision to
remove two regions from the rotation. We have updated the asset region list to remove
both SOUTHEAST_ASIA and CENTRAL_INDIA. The updated list of available regions can
be found below.
1. WEST_US (West US)
2. EAST_US_NORTH (Northeastern US)
3. EAST_US_SOUTH (Southeastern US)
4. CENTRAL_US (Central US)
5. SOUTH_CENTRAL_US (South Central US)
6. SOUTH_AMERICA (South America)
7. NORTH_EUROPE (North Europe)
8. WEST_EUROPE (West Europe)



Oct 11, 2022

Introducing the Live Events Development Tier
We are proud to introduce the Live Events API Program to a broader audience. Starting
today, all partners may request access to Live Events APIs through
developer.linkedin.com    .



Sept. 3, 2021

Migration from /organizationalEntityAcls to
/organizationAcls
In order to go live from a Page, you first need to identify the Page's organization urn.
The organizationalEntityAcls service has been marked for deprecation by November
2021, and will be replaced with organizationAcls . Follow the steps below to migrate
your apps to use the new service.


organizationalEntityAcls Request

  curl


  https://api.linkedin.com/v2/organizationalEntityAcls?
  q=roleAssignee&role=ADMINISTRATOR&projection=(elements*
  (organizationalTarget~))




organizationAcls Request

  curl


  https://api.linkedin.com/v2/organizationAcls?q=roleAssignee&projection=
  (elements*(organization~))




Scheduled Live Events Updates
We've clarified a few points in the Scheduled Live Events documentation where we've
seen recent issues crop up.

   1. The name or title of the scheduled live event has a max character limit of 75 chars.
   2. We've added a note that live event assets can only be used once their state has
         transitioned to the AVAILABLE state.



July 1, 2021

Migration from /assets to /liveAssetActions
In efforts to improve performance and stability of live event broadcasts, we are
introducing a new /liveAssetActions API to handle all requests to register, and end live
events. To get started with the new service, you will need to make a few changes to your
existing requests to /assets. The /liveAssetActions API will only serve to replace requests
to register and end live events. There are no changes to retrieve asset status.

   1. Update the resource name from /assets to /liveAssetActions .
   2. Update ?action=registerLiveEvent to ?action=register . No changes to the
      request or response bodies.
   3. Update ?action=endLiveEvent to ?action=end . The asset URN must now be
      provided in the request body. See End the Live Event for reference.


Typeahead for Bing Geo
      GeoTypeahead API '/geoTypeahead?q=federated' will be deprecated on August
      31, 2021. Please use GeoTypeahead API '/geoTypeahead?q=search' to find the best
      matching geo URNs.



May 3, 2021

Deprecating Connections-Only feature
When creating ugcPosts you have the option of identifying the visibility as PUBLIC or
CONNECTIONS . Going forward, we are removing the CONNECTIONS scope. Ensure the
visibility of your ugcPosts follows the format:


  JSON


         "visibility": {
             "com.linkedin.ugc.MemberNetworkVisibility": "PUBLIC"
         }



Additionally, all requests to register a new live event must use the recipe:
urn:li:digitalmediaRecipe:feedshare-live-video . Any request to POST assets?

action=registerLiveEvent should remove the option of using feedshare-live-video-
private .



New Scheduled Live Events name Parameter
We are now providing an easier way for you to manage scheduled live events. A name
parameter has been added to the liveVideos schema. This field serves to be the new title
of the live event, and will eventually replace the existing live event asset title. Example
liveVideos request below:


  JSON


  {
      "author": {
          "member": "urn:li:person:iKO_ntS9UQ"
        },
        "scheduledAt": 1591892529000,
        "announcementImage": {
          "media": "urn:li:digitalmediaAsset:C5F22AQEUvl4IOBjE2g",
          "title": {
            "text": "Image title",
            "inferredLocale": "en_US"
          }
        },
        "name": "Scheduled Live Event title"
  }




Removing Scheduled Live Events Time Restriction
Removed time constraints from liveVideos creation. There is no longer a minimum 1
hour, or 7 day maximum time constraint for new scheduled live events.


Deprecating legacy Live Events feature
Current: Schedule a livestream (scheduled live) AND go live into an event flow (multi-
step copy/paste event URL flow) New: ONLY scheduled live flow will exist.

You may have integrated a feature where you ask your members for the URL of their
LinkedIn Event, use this URL to obtain an Event URN, and input this Event URN in a
ugcPost container. This flow is marked for deprecation in favor of the scheduled live
flow.


Refresh Tokens
An often requested feature has been the ability to use OAuth refresh tokens, preventing
the need for broadcasters to authorize their account every 60 days. We are now offering
this capability to all Live Events Partners. Reach out to your LinkedIn contact to enable
this feature on your developer application.
