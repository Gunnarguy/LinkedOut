# Share on LinkedIn

Overview
LinkedIn is a powerful platform to share content with your social network. Ensure your
content receives the professional audience it deserves using Share on LinkedIn.

Use Share on LinkedIn to:

      Get your content in front of an audience of millions of professionals.
      Drive traffic to your site and grow your member base.
      Benefit from having your content shared across multiple professional networks
      worldwide.




Getting Started

Authenticating Members
New members Sharing on LinkedIn from your application for the first time will need to
follow the Authenticating with OAuth 2.0 Guide. When requesting an authorization code
in Step 2 of the OAuth 2.0 Guide, make sure to request the w_member_social scope!


                                                                                ﾉ   Expand table


 Permission Name       Description

 w_member_social       Required to create a LinkedIn post on behalf of the authenticated member.


After successful authentication, you will acquire an access token that can be used in the
next step of the share process.

If your application does not have this permission, you can add it through the Developer
Portal   . Select your app from My Apps        , navigate to the Products tab, and add the
Share on LinkedIn product which will grant you w_member_social .



Creating a Share on LinkedIn
There are multiple ways to share content with your LinkedIn network. In this guide, we
will show you how to create shares using text, URLs, and images. For all shares created
on LinkedIn, the request will always be a POST request to the User Generated Content
(UGC) API.


API Request
  HTTP


  POST https://api.linkedin.com/v2/ugcPosts




  ７ Note

  All requests require the following header: X-Restli-Protocol-Version: 2.0.0




Request Body Schema

                                                                                  ﾉ   Expand table


 Field Name        Description                                   Format                    Required

 author            The author of a share contains Person         Person URN                Yes
                   URN of the Member creating the share.
                   See Sign In with LinkedIn using OpenID
                   Connect to see how to retrieve the
                   Person URN.

 lifecycleState    Defines the state of the share. For the       string                    Yes
                   purposes of creating a share, the
                   lifecycleState will always be PUBLISHED .

 specificContent   Provides additional options while             ShareContent              Yes
                   defining the content of the share.

 visibility        Defines any visibility restrictions for the   MemberNetworkVisibility   Yes
                   share. Possible values include:
                          CONNECTIONS - The share will be
                         viewable by 1st-degree
                         connections only.
                          PUBLIC - The share will be
                         viewable by anyone on LinkedIn.
Share Content

                                                                                         ﾉ   Expand table


 Field Name             Description                                             Format          Required

 shareCommentary        Provides the primary content for the share.             string          Yes

 shareMediaCategory     Represents the media assets attached to the             string          Yes
                        share. Possible values include:
                               NONE - The share does not contain any
                               media, and will only consist of text.
                               ARTICLE - The share contains a URL.
                               IMAGE - The Share contains an image.



 media                  If the shareMediaCategory is ARTICLE or                 ShareMedia[]    No
                         IMAGE , define those media assets here.




Share Media

                                                                                         ﾉ   Expand table


 Field         Description                                             Format                   Required
 Name

 status        Must be configured to READY .                           string                   Yes

 description   Provide a short description for your image or           string                   No
               article.

 media         ID of the uploaded image asset. If you are              DigitalMediaAsset        No
               uploading an article, this field is not required.       URN

 originalUrl   Provide the URL of the article you would like to        string                   No
               share here.

 title         Customize the title of your image or article.           string                   No




Create a Text Share
The example below creates a simple text Share on LinkedIn. Notice the visibility is set to
PUBLIC, where anyone on the LinkedIn Platform can view this share.
Sample Request Body

  JSON


  {
         "author": "urn:li:person:8675309",
         "lifecycleState": "PUBLISHED",
         "specificContent": {
             "com.linkedin.ugc.ShareContent": {
                 "shareCommentary": {
                     "text": "Hello World! This is my first Share on LinkedIn!"
                 },
                 "shareMediaCategory": "NONE"
             }
         },
         "visibility": {
             "com.linkedin.ugc.MemberNetworkVisibility": "PUBLIC"
         }
  }




Response

A successful response will return 201 Created , and the newly created post will be
identified by the X-RestLi-Id response header.




Create an Article or URL Share
The example below illustrates various options when Sharing an Article or URL. The
request body is similar to the Text Share above, however, we have now specified a media
parameter containing the URL, title, and description. Keep in mind the title and
description are optional parameters.



Sample Request Body

  JSON


  {
      "author": "urn:li:person:8675309",
      "lifecycleState": "PUBLISHED",
      "specificContent": {
          "com.linkedin.ugc.ShareContent": {
              "shareCommentary": {
                  "text": "Learning more about LinkedIn by reading the
  LinkedIn Blog!"
              },
              "shareMediaCategory": "ARTICLE",
              "media": [
                  {
                      "status": "READY",
                      "description": {
                          "text": "Official LinkedIn Blog - Your source for
  insights and information about LinkedIn."
                      },
                      "originalUrl": "https://blog.linkedin.com/",
                      "title": {
                          "text": "Official LinkedIn Blog"
                      }
                  }
              ]
          }
      },
      "visibility": {
          "com.linkedin.ugc.MemberNetworkVisibility": "PUBLIC"
      }
  }




Response
A successful response will return 201 Created , and the newly created post will be
identified by the X-RestLi-Id response header.




Create an Image or Video Share
If you'd like to attach an image or video to your share, you will first need to register,
then upload your image/video to LinkedIn before the share can be created. We will walk
through the following steps to create the share:

   1. Register your image or video to be uploaded.
   2. Upload your image or video to LinkedIn.
   3. Create the image or video share.


Register the Image or Video
Send a POST request to the assets API, with the action query parameter to
registerUpload .


  HTTP


  POST https://api.linkedin.com/v2/assets?action=registerUpload
Similar to the author parameter we've used with the ugcPosts API, we will need to
provide our Person URN. Additional recipes and serviceRelationships define the type
of content we're publishing. For Share on LinkedIn, recipes will always contain either the
type feedshare-image or the type feedshare-video (depending on which of the two you
are uploading) and serviceRelationships will always define the relationshipType and
identifier. See the request body below for reference.

  JSON


  {
         "registerUploadRequest": {
             "recipes": [
                 "urn:li:digitalmediaRecipe:feedshare-image"
             ],
             "owner": "urn:li:person:8675309",
             "serviceRelationships": [
                 {
                     "relationshipType": "OWNER",
                     "identifier": "urn:li:userGeneratedContent"
                 }
             ]
         }
  }



A successful response will contain an uploadUrl and asset that you will need to save for
the next steps.

  JSON


  {
      "value": {
          "uploadMechanism": {
              "com.linkedin.digitalmedia.uploading.MediaUploadHttpRequest": {
                  "headers": {},
                  "uploadUrl":
  "https://api.linkedin.com/mediaUpload/C5522AQGTYER3k3ByHQ/feedshare-
  uploadedImage/0?
  ca=vector_feedshare&cn=uploads&m=AQJbrN86Zm265gAAAWemyz2pxPSgONtBiZdchrgG872
  QltnfYjnMdb2j3A&app=1953784&sync=0&v=beta&ut=2H-IhpbfXrRow1"
              }
          },
          "mediaArtifact": "urn:li:digitalmediaMediaArtifact:
  (urn:li:digitalmediaAsset:C5522AQGTYER3k3ByHQ,urn:li:digitalmediaMediaArtifa
  ctClass:feedshare-uploadedImage)",
          "asset": "urn:li:digitalmediaAsset:C5522AQGTYER3k3ByHQ"
      }
  }
Upload Image or Video Binary File
Using the uploadUrl returned from Step 1, upload your image or video to LinkedIn. To
upload your image or video, send a POST request to the uploadUrl with your image or
video included as a binary file. The example below uses cURL to upload an image file.



Sample Request

  Bash


  curl -i --upload-file /Users/peter/Desktop/superneatimage.png --header
  "Authorization: Bearer redacted"
  'https://api.linkedin.com/mediaUpload/C5522AQGTYER3k3ByHQ/feedshare-
  uploadedImage/0?
  ca=vector_feedshare&cn=uploads&m=AQJbrN86Zm265gAAAWemyz2pxPSgONtBiZdchrgG872
  QltnfYjnMdb2j3A&app=1953784&sync=0&v=beta&ut=2H-IhpbfXrRow1'




Create the Image or Video Share
After the image or video file has successfully uploaded from Step 2, we will use the
asset from Step 1 to attach the image to our share. Below is a sample request for an

image; for a video, the shareMediaCategory should be VIDEO instead of IMAGE.



Sample Request Body

  JSON


  {
      "author": "urn:li:person:8675309",
      "lifecycleState": "PUBLISHED",
      "specificContent": {
          "com.linkedin.ugc.ShareContent": {
              "shareCommentary": {
                  "text": "Feeling inspired after meeting so many talented
  individuals at this year's conference. #talentconnect"
              },
              "shareMediaCategory": "IMAGE",
              "media": [
                  {
                      "status": "READY",
                      "description": {
                          "text": "Center stage!"
                      },
                      "media": "urn:li:digitalmediaAsset:C5422AQEbc381YmIuvg",
                      "title": {
                          "text": "LinkedIn Talent Connect 2021"
                            }
                     }
                 ]
           }
       },
       "visibility": {
           "com.linkedin.ugc.MemberNetworkVisibility": "PUBLIC"
       }
  }




Response
A successful response will return 201 Created , and the newly created post will be
identified by the X-RestLi-Id response header.



Rate Limits
                                                                        ﾉ   Expand table


 Throttle Type                     Daily Request Limit (UTC   )

 Member                            150 Requests

 Application                       100,000 Requests




Feedback
Was this page helpful?      Yes    No


Provide product feedback
Verified on LinkedIn – Overview
The Verified on LinkedIn API allows you to access trusted verification signals from LinkedIn
members, enabling you to display verified identity and workplace information directly within
your platform.

Today, more than 100 million LinkedIn members have confirmed their identity with a
government-issued ID or verified their workplace using a company email. Read more about
LinkedIn verifications   .

Build trust and authenticity into your platform by leveraging LinkedIn's verification ecosystem,
helping you distinguish real professionals from fraudulent accounts.


Watch the Verified on LinkedIn overview video
Try it Now - It only takes 10 minutes
It just takes 10 minutes to make your first API call. Refer to our Quickstart Guide.




Use Cases

What Verified on LinkedIn Can Be Used For

                                                                                            ﾉ    Expand table


 Category                  Examples

 Trust & Safety            Professional communities, networking platforms, online marketplaces, peer-to-
                           peer exchanges

 Communities &             Event registration, professional conferences, community moderation, alumni
 Networks                  groups

 Marketplaces              Buyer/seller verification, freelance platforms, service-sharing, resale platforms



What Verified on LinkedIn Cannot Be Used For
The API is designed for trust enhancement, not regulatory compliance or eligibility decisions.
Use of the API is subject to LinkedIn's Developer Terms and Verification Policies.


                                                                                            ﾉ    Expand table


 Restricted Use Case                    Reason

 Hiring or employment decisions         Not an employment screening tool. Do not use to rank or approve
                                        candidates.

 Background checks                      Does not include criminal, financial, or government background
                                        data.

 Credit, loans, or insurance            Not related to creditworthiness or insurability.

 Housing eligibility                    Cannot be used for rental or housing determinations.

 Fintech or banking KYC                 Not a regulated KYC/AML service.

 Government or regulated identity       Not a substitute for official ID verification systems.
 checks
 Restricted Use Case                       Reason

 Platform safety or risk scoring           Should complement — not replace your platform's trust and risk
                                           systems.




Choose Your Tier
LinkedIn offers three tiers of the Verified on LinkedIn API, each designed for different use cases
and stages of development.


                                                                                              ﾉ   Expand table


 Tier            Best For           Access                     Cost          Rate        Get Started
                                                                             Limits

 Development     Testing &          Developer app              Free          5,000/day   Development Tier
                 prototyping        admins only                                          Quickstart (10 min)

 Lite            SMBs &             All LinkedIn               Free          5,000/day   Lite Tier Quickstart
                 startups           members

 Plus            Enterprise         All LinkedIn               Contact       Custom      Plus Tier Quickstart
                 partners           members +                  us
                                    enhanced data



Detailed Tier Comparison

                                                                                              ﾉ   Expand table


 Feature             Development               Lite                   Plus

 Access Type         Self-serve                Application            Business Development approval
                     (automatic)               review

 Member Data         Developer app             All LinkedIn           All LinkedIn members
 Access              admins only               members

 Production          ❌ Testing only            ✅ Yes                  ✅ Yes
 Ready

 Profile Data        Basic profile info        Basic profile info     Basic profile info + Current experience +
                                                                      Recent education

 Verification        Verified categories       Verified               Verified Categories + Details +
 Details             only                      categories only        Timestamps
Feature             Development            Lite                Plus

Bulk Validation     ❌                      ❌                   Validate if the member data has changed
API                                                            and needs to be refreshed

Push                ❌                      ❌                   Get push notification events when a
Notifications                                                  member data has changed



 ７ Note

 For Plus tier pricing and partnership inquiries, contact LinkedIn Business Development                    .




Verification Types
                                                                                        ﾉ   Expand table


Type               Description                 Methods                  Data Available

Identity           Confirms the member's       Government-issued ID     Verified Categories (all tiers),
Verification       real identity                                        Verification details (Plus tier)

Workplace          Confirms current            Work email, Microsoft    Verified Categories (all tiers),
Verification       association with a          Entra Verified ID        Organization details (Plus tier)
                   company




How It Works
    Member Authorizes: Grants your app permission to access their LinkedIn verification data
    via OAuth 2.0.
    Fetch Verification Data: Call LinkedIn APIs to retrieve verification status and profile
    information.
    Display Verification Badges: Show "Verified on LinkedIn" badges in your UI following our
    branding guidelines if the member is verified.




Quick Navigation

By Role
                                                                                          ﾉ    Expand table


 Who You Are                    Where to Start

 Developer                      Pick a quickstart → API Reference → Implementation Guide

 Product Manager                Use Cases → Tier comparison (above) → Pick a quickstart

 Marketing & Design             Branding Guidelines → Use Cases



By Goal

                                                                                          ﾉ    Expand table


 I Want To...                             Go Here

 Test the API quickly                     Quickstart (Development Tier) - 10 minutes

 Launch in production                     Upgrade to Lite Tier

 Get enterprise features                  Plus Tier Quickstart

 See API docs                             API Reference

 Understand use cases                     Use Cases

 Display badges correctly                 Branding Guidelines




API Reference
All tiers use the same API endpoints with different access levels:


                                                                                          ﾉ    Expand table


 API                    Purpose          Development      Lite            Plus

 /identityMe            Profile data     Basic profile    Basic profile   Basic profile + current Experience
                                                                          + recent Education

 /verificationReport    Verification     Categories       Categories      Categories + Verification details
                        status           only             only

 /validationStatus      Bulk             ❌                ❌               Validation statuses of Profile +
                        validation                                        Verification Information


View complete API reference →
Getting Started

Step 1: Choose Your Tier
Review the tier comparison table above to find the right tier for your needs.


Step 2: Follow the Quickstart
     Quickstart (Development Tier) - Test with developer app admins (10 min)
     Upgrade to Lite Tier - Production for SMBs
     Plus Tier Quickstart - Enterprise features


Step 3: Implement & Launch
     Follow the Implementation Guide for API Integration, OAuth, testing, and production best
     practices.
     Review Branding Guidelines
     Check our FAQ for common questions




Support & Resources

Documentation
     API Reference - Complete API documentation
     Common FAQ - Frequently asked questions
     Release Notes - API updates and changes


Tools
     Sample App      - Test OAuth flow and API calls
     Developer Portal      - Manage your applications
     OAuth Tool     - Generate test tokens


Help
     LinkedIn API Status     - Monitor API health
     Partner Support - Get help from LinkedIn team
Last updated on 12/10/2025
Quickstart on Development Tier
Get started quickly with the Verified on LinkedIn APIs in 10 minutes using the Development
tier. This tier is designed for rapid prototyping and internal testing using your own LinkedIn
administrator accounts.


  ２ Warning

  Development tier is for testing only.
  It can access only LinkedIn members who are application administrators.
  Upgrade to Lite tier to access all LinkedIn members. Lite tier reviews typically complete
  within a week.




Development Tier Capabilities
The table below summarizes what the Development tier includes and what it does not—
covering access, usage limits, and available APIs.


                                                                                          ﾉ   Expand table


 Capability / API Access               Development     Notes
                                       Tier

 Access to your own admin              Available       Only app administrators can be queried
 accounts

 Access to all LinkedIn members        Not available   Requires Lite or Plus tier

 Use in production                     Not allowed     Intended only for testing

 3-legged OAuth testing                Yes             Full OAuth flow supported

 UI badge integration testing          Yes             For development environments only

 API: /identityMe                      Available       Basic profile info (name, email, photo, profile
                                                       URL)

 API: /verificationReport              Available       Verification categories only

 API: /validationStatus                Not available   Plus tier only (bulk validation)

 Cost                                  Free            For testing purposes


For full tier details, see Overview.
Start Building Now

Prerequisites
Before you begin, you’ll need:

     A LinkedIn account
     Add at least one verification (Identity or Workplace) at linkedin.com/verify   to your
     profile to test the verification APIs with real data.




Step 1: Create Developer Application (2 minutes)
Create a LinkedIn developer application to get your API credentials and enable the Verified on
LinkedIn product in the Developer Portal.

Follow these steps:

   1. Go to the LinkedIn Developer Portal
   2. Click Create app
   3. Fill in the required fields and create your application


How to Create a Developer Application and Add an API

https://share.vidyard.com/watch/5BdUkDzHt7HXEvWSzvckmV


  ７ Note

  App logo requirement: The logo must be a square image, and at least one dimension
  must be 100px or larger.
  If you don’t have a logo ready, you can use a temporary demo logo for quick setup.


Download a sample demo logo:
Download demo app logo

This is the starting point for both Development and Lite tier integrations.

     When to complete: before requesting Development or Lite tier access
     Learn more about Verified on LinkedIn
     Related docs: Overview, Upgrade to Lite tier.
Step 2: Request Development Tier Access (1 minute)
   1. In your new app, go to the Products tab
   2. Find Verified on LinkedIn in the product list
   3. Click Request access
   4. Review and accept Terms and Conditions
   5. Automatic approval - Refresh page after 1-2 minutes to see status change


  ７ Note

  Development tier is provisioned automatically. No review required!




Step 3: Get Your Credentials (1 minute)
   1. Go to the Auth tab in your app
   2. Copy these credentials (you'll need them):

            Client ID
            Client Secret


  ２ Warning

  Keep your Client Secret secure. Never expose it in client-side code or public repositories.




Step 4: Test with Sample App (Optional)
This video walks you through using the sample application to test the Verified on LinkedIn APIs
end-to-end — including running the OAuth flow, reviewing verification responses, and seeing
how badges appear in UI examples. It’s an easy way to validate your credentials before writing
any code.

Try our Sample App      to see your credentials in action:

     Test OAuth flow securely
     View real verification responses
     See verification badge display examples
  ７ Note

  The sample app does not store or share your credentials.


https://share.vidyard.com/watch/vHLNdwNesP86um3eqdfyDo




Step 5: Generate Access Token (3-legged OAuth)
This video explains how LinkedIn OAuth works for Verified on LinkedIn, including scopes,
redirects, and token exchange.

https://share.vidyard.com/watch/1P3fKJ3ZVnrmEWfutkNp2p

To generate a token during development:



Option A: Use OAuth Tool (Fastest)

   1. Go to OAuth Tool    and select your developer app
   2. Select scopes: r_profile_basicinfo and r_verify
   3. Click Request access token
   4. Authorize with your LinkedIn account
   5. Copy the generated access token

https://share.vidyard.com/watch/4BUUmNu86a67bMuGhgtikT


Option B: Build OAuth Flow (Production-Ready)

For production use, implement the full 3-legged OAuth flow in your application:

   1. Review the authentication documentation for the complete OAuth sequence, including
     authorization, token exchange, and refresh handling.
   2. Follow the integration best practices guide for secure token storage, redirect handling,
     and recommended architecture.


   Tip

  Always exchange authorization codes for access tokens on your server, and never expose
  your client secret in client-side code.
Step 6: Call the APIs

Try the APIs instantly (Postman)
Use our Postman collection to call /identityMe and /verificationReport without writing code.




   Tip

  You can make your first API call in under 10 minutes using Development tier with admin-
  only data.




Making an API call

This video demonstrates how to call the Verified on LinkedIn APIs with a valid access token and
interpret the response. It complements the /identityMe and /verificationReport API
reference pages.

      When to watch: once OAuth is working and you’re ready to test real API calls.
      Related docs: Profile Details API (/identityMe), Verification Report API (/verificationReport).

https://share.vidyard.com/watch/zAZ1MLqX3LVzjUgDaTA8ni


Test Profile API

Get basic profile information:


 Bash
 curl -X GET 'https://api.linkedin.com/rest/identityMe' \
   -H 'Authorization: Bearer {YOUR_ACCESS_TOKEN}' \
   -H 'LinkedIn-Version: {LATEST_VERSION}'


Sample Response:


 JSON

 {
     "id": "abc123",
     "lastRefreshedAt": 1760631246905,
     "basicInfo": {
       "firstName": {
           "localized": { "en_US": "John" },
           "preferredLocale": { "country": "US", "language": "en" }
         },
         "lastName": {
           "localized": { "en_US": "Doe" },
           "preferredLocale": { "country": "US", "language": "en" }
         },
         "primaryEmailAddress": "john.doe@example.com",
         "profileUrl": "https://www.linkedin.com/profile-thirdparty-redirect/...",
         "profilePicture": {
           "croppedImage": {
             "downloadUrl": "https://media.licdn.com/dms/image/...",
             "downloadUrlExpiresAt": 1763596800000
           }
         }
     }
 }




Test Verification Report API
Check your verification status:


 Bash
 curl -X GET 'https://api.linkedin.com/rest/verificationReport' \
   -H 'Authorization: Bearer {YOUR_ACCESS_TOKEN}' \
   -H 'LinkedIn-Version: {LATEST_VERSION}'


Sample Response:


 JSON
 {
     "id": "abc123",
     "verifications": ["IDENTITY", "WORKPLACE"]
 }



  ７ Note

  See Release Notes for current API versions.




Understanding Your Limitations
                                                                           ﾉ   Expand table
 What You Can Do                                What You Cannot Do

 Test with application administrators           Access data for other LinkedIn members

 Build and test integration                     Use in production

 Test OAuth flow end-to-end                     Access data for end users

 Display verification badges                    Scale beyond testing

 Test all API endpoints                         Serve production traffic



  ） Important

  Application Administrator Access Only:
  Development tier can only access verification data for LinkedIn members who are
  administrators of your developer application.

  To test with additional LinkedIn accounts, add them as application administrators in
  Developer Portal → Your App → Team members tab.




When You're Ready to Upgrade
Ready for production access? Upgrading to Lite tier is straightforward. For detailed upgrade
instructions, see Lite Tier Quickstart.


  ７ Note

  Your Development tier integration will continue to work on Lite tier with no code changes.
  Lite tier uses the same APIs and implementation as Development tier, and reviews typically
  complete within a week.


For detailed upgrade instructions, see Lite Tier Quickstart.




Next Steps

Continue Testing
     Implementation Guide - OAuth, tokens, best practices
API References
     /identityMe API - Profile details endpoint
     /verificationReport API - Verification details endpoint
     Authentication - OAuth details


Ready for Production?
     Upgrade to Lite Tier - Production access guide
     Overview - Compare tier features


Resources
     Branding Guidelines - Display badges correctly
     FAQ - Frequently asked questions




Troubleshooting

"Insufficient permissions to access" Error
Cause: Trying to access data for a LinkedIn member who is not an administrator of your
developer application

Solution:

   1. Use a LinkedIn account that is an application administrator, OR
   2. Add test accounts as application administrators in Developer Portal → Team members
     tab, OR
   3. Upgrade to Lite tier to access all LinkedIn members


"Invalid access token" Error
Cause: Token expired or invalid

Solution:

   1. Generate a new token using the OAuth tool
   2. Implement token refresh logic for production
   3. See Authentication Guide for token refresh details
"Product not assigned" Error
Cause: Verified on LinkedIn product not enabled

Solution:

   1. Go to Developer Portal → Your App → Products tab
   2. Ensure "Verified on LinkedIn" shows as Approved
   3. Refresh page if just requested



🎉 Congratulations! You're now testing Verified on LinkedIn APIs. When you're ready for
production, upgrade to Lite tier.



 Last updated on 12/08/2025
Upgrade to Lite Tier
Upgrade to production-ready access by moving from Development to Lite tier. Lite tier uses
the same APIs as Development tier, but allows you to access verification data for all LinkedIn
members instead of just developer app administrators.


  ） Important

  Lite tier is identical to Development tier in terms of APIs and implementation. The only
  difference: you can now access all LinkedIn members instead of just developer app
  administrators. No code changes required!




How the upgrade process works
End-to-end upgrade flow:

   1. Submit an upgrade request from the Developer Portal.
   2. Provide your business details as part of the request.
   3. Complete a short LinkedIn survey.
   4. LinkedIn reviews your request (typically within 1 week).
   5. Once approved, your app is automatically enabled for Lite tier access.

[!NOTE]

  This process makes your integration production-ready. Your API endpoints, scopes, and
  implementation remain unchanged.




Overview

Lite Tier Capabilities
The table below summarizes what the Lite tier includes and what it does not—covering access
level, API availability, and feature limitations.


                                                                                   ﾉ   Expand table


 Capability / API Access                      Lite Tier   Notes

 Production access                            Available   Can be used to serve real end users
 Capability / API Access                          Lite Tier         Notes

 Access to all LinkedIn members                   Available         Not limited to application administrators

 Same APIs as Development tier                    Yes               No code changes required

 API: /identityMe                                 Available         Profile and verification-linked identity data

 API: /verificationReport                         Available         Verification categories

 Same rate limits as Development                  Yes               5,000 calls/day (application-level)

 Advanced profile data (education, jobs)          Not available     Plus tier only

 Bulk validation API: /validationStatus           Not available     Plus tier only

 Detailed verification metadata (timestamps)      Not available     Plus tier only



API Access

                                                                                               ﾉ    Expand table


 Endpoint                   Available                   Response Data

 /identityMe                Yes                         Basic profile (name, email, photo, profile URL)

 /verificationReport        Yes                         Verification categories only

 /validationStatus          No (Plus tier only)         Bulk member validation



OAuth Scopes

                                                                                               ﾉ    Expand table


 Scope                            Available       Purpose

 r_profile_basicinfo              Yes             Basic profile information

 r_verify                         Yes             Verification categories (not detailed metadata)


For OAuth scopes and rate limits, see the API reference documentation:

     /identityMe
     /verificationReport
Prerequisites
Before requesting Lite tier access:

     ✅ Development tier access - Must have tested with Development tier first
     ✅ Valid use case - Clear business need for verification data
     ✅ Working integration - Tested integration with Development tier

  ７ Note

  You must start with Development tier before upgrading to Lite. Learn more about tier
  progression.




Step 1: Test with Development Tier (If Not Done)
If you haven't already:

   1. Complete the Quickstart Guide
   2. Test OAuth flow and API calls
   3. Validate your integration works correctly




Step 2: Request Lite Tier Upgrade
Submitting the request typically takes only a few minutes. Review and approval typically
complete within a week.


2.1 Click Request Upgrade
   1. Go to LinkedIn Developer Portal
   2. Select your application
   3. Navigate to Products tab
   4. Find Verified on LinkedIn (should show "Development Tier" status)
   5. Click Request upgrade


2.2 Accept Terms and Verify Email
   1. Review and accept Verified on LinkedIn Terms and Conditions
   2. Verify your business email address
   3. An Access Request Form link will appear


2.3 Complete Access Request Form
Click the Access Request Form link and provide necessary details about your application,
company, use case, and technical implementation.


   Tip

  Be specific: Clear, detailed use cases receive faster approval. Explain exactly how
  verification data improves your user experience.



2.4 Submit and Wait for Approval
     Review time: Typically less than a week
     Notification: You'll receive email when approved
     Status: Check Products tab for status updates




Step 3: Configure Production Settings
Once approved, configure your production environment:


3.1 Verify OAuth Scopes
Ensure these scopes are authorized:

     r_profile_basicinfo - Basic profile info

     r_verify - Verification status



3.2 Add Production Redirect URIs
   1. Go to Auth tab
   2. Under Authorized redirect URLs, add your production URLs:

           https://yourdomain.com/auth/linkedin/callback
           https://yourdomain.com/oauth/callback



  ２ Warning
  Only HTTPS URLs are allowed. HTTP URLs will be rejected.



3.3 Secure Your Credentials
     ✅ Store Client Secret in environment variables or secret manager
     ✅ Never commit credentials to version control
     ✅ Use different credentials for staging and production
     ✅ Implement token encryption at rest



Step 4: Deploy to Production

4.1 Update OAuth Flow
Your Development tier code will work with Lite tier. The only change is access scope:


 JavaScript
 // Same OAuth flow - now works for all LinkedIn members
 const authUrl = `https://www.linkedin.com/oauth/v2/authorization?
 response_type=code&client_id=${clientId}&redirect_uri=${redirectUri}&scope=r_profile
 _basicinfo%20r_verify&state=${state}`;




4.2 Test with Real Users
   1. Have non-admin LinkedIn members test your integration
   2. Verify OAuth consent flow works correctly
   3. Test API calls return expected data
   4. Verify verification badges display correctly


4.3 Monitor API Usage
Track your API usage to stay within rate limits:

     Application-level: 5,000 calls/day
     Member-level: 500 calls/day per member


   Tip
  Implement caching and token refresh to optimize API usage. See Implementation Guide
  for best practices.




Step 5: Call the APIs
The API calls are identical to Development tier:


Get Profile Data

 Bash
 curl -X GET 'https://api.linkedin.com/rest/identityMe' \
   -H 'Authorization: Bearer {ACCESS_TOKEN}' \
   -H 'LinkedIn-Version: {LATEST_VERSION}'




Get Verification Report

 Bash
 curl -X GET 'https://api.linkedin.com/rest/verificationReport' \
   -H 'Authorization: Bearer {ACCESS_TOKEN}' \
   -H 'LinkedIn-Version: {LATEST_VERSION}'


Sample Response:


 JSON
 {
     "id": "abc123",
     "verifications": ["IDENTITY", "WORKPLACE"]
 }




Quickly validate your integration using the Verified on LinkedIn Postman collection.




Production Best Practices
Security
     ✅ Encrypt tokens at rest
     ✅ Use HTTPS only
     ✅ Implement CSRF protection (state parameter)
     ✅ Rotate secrets regularly

Performance
     ✅ Cache API responses appropriately
     ✅ Implement token refresh before expiry
     ✅ Use exponential backoff for retries
     ✅ Monitor rate limits


User Experience
     ✅ Follow branding guidelines
     ✅ Handle unverified members gracefully
     ✅ Provide clear consent messaging
     ✅ Test mobile responsiveness

   Tip

  For comprehensive production guidelines, see Implementation Guide.




When You're Ready to Upgrade

Upgrade to Plus Tier When:
✅ Need detailed verification metadata (timestamps, methods)
✅ Need education and job title data
✅ Need bulk validation API ( /validationStatus )
✅ Enterprise-scale requirements


How to Upgrade:
Plus tier requires partnership discussions with LinkedIn. Contact your LinkedIn representative or
visit the Plus Tier Guide for more information.
Next Steps

Optimize Your Integration
     Implementation Guide - OAuth, tokens, error handling


API References
     /identityMe API - Profile details endpoint
     /verificationReport API - Verification details endpoint
     Authentication - OAuth details


Consider Plus Tier
     Plus Tier Guide - Enterprise features
     Overview - Compare all tiers


Resources
     Branding Guidelines - Display badges correctly
     FAQ - Frequently asked questions
     Release Notes - API updates and changes




Troubleshooting

"Access request pending" Status
Cause: Application under review

Solution:

     Wait for email notification (typically within a week)
     Check Products tab for status updates


"Insufficient permissions" Error
Cause: Your app is not yet approved for Lite tier or the access token was issued before Lite tier
approval.

Solution:

   1. Verify Lite tier is approved in Products tab
   2. Regenerate access token with correct scopes
   3. Ensure using production redirect URIs


Rate Limit Exceeded
Cause: Exceeded 5,000 calls/day (application) or 500 calls/day (member)

Solution:

   1. Implement caching to reduce API calls
   2. Use token refresh instead of re-authorization
   3. Monitor usage and optimize call patterns
   4. Consider upgrading to Plus tier for higher limits



🎉 Congratulations! You're now production-ready with Verified on LinkedIn Lite tier. For
enterprise features, contact your LinkedIn representative.



 Last updated on 12/08/2025
Plus Tier Quickstart
Get from zero to your first successful API call displaying detailed verification data in 15
minutes. Plus tier provides enterprise-grade features including full profile data, detailed
verification metadata, and bulk validation capabilities.


  ） Important

  Enterprise Partnership Required

  Plus tier access requires approval from LinkedIn Business Development. This tier is
  designed for enterprise partners with strategic use cases.




Overview

What You'll Get
✅ Full profile data - Current job, education, and professional details
✅ Detailed verification metadata - Verified names, timestamps, methods, organization info
✅ Bulk validation API - Check freshness for up to 500 members per request
✅ Custom rate limits - Enterprise-scale API access
✅ Priority support - Dedicated partner support team


API Access

                                                                                       ﾉ   Expand table


 Endpoint                Available     Response Data

 /identityMe             ✅ Yes         Full profile (name, email, photo, URL, education, job)

 /verificationReport     ✅ Yes         Detailed verification metadata with timestamps

 /validationStatus       ✅ Yes         Bulk member validation (up to 500 members)



OAuth Scopes

                                                                                       ﾉ   Expand table
 Scope                              Available     Purpose

 r_profile_basicinfo                ✅ Yes         Basic profile information

 r_verify_details                   ✅ Yes         Detailed verification metadata with timestamps

 r_primary_current_experience       ✅ Yes         Current job title and company

 r_most_recent_education            ✅ Yes         Most recent education information



Rate Limits
     Custom limits - Negotiated based on partnership agreement
     Bulk validation - Up to 500 members per /validationStatus request




Prerequisites
Before starting, ensure you have:

     ✅ Approved partner access from LinkedIn Business Development
     ✅ Developer application created in LinkedIn Developer Portal
     ✅ Client ID and Client Secret from your app's Auth tab
     ✅ Verified on LinkedIn Plus product enabled for your application

   Tip

  To request access, visit Verified on LinkedIn     and submit an access request        .




Step 1: Set Up OAuth (2 minutes)

Configure Redirect URI
   1. Go to Developer Portal    → Your App → Auth tab
   2. Add your redirect URI (e.g., https://yourapp.com/auth/linkedin/callback )
   3. Note your Client ID and Client Secret


Request Authorization
Redirect the member to LinkedIn's authorization page with all required scopes:


 HTTP

 GET https://www.linkedin.com/oauth/v2/authorization
   ?response_type=code
   &client_id={YOUR_CLIENT_ID}
   &redirect_uri={YOUR_REDIRECT_URI}
   &state={RANDOM_STRING}

 &scope=r_verify_details%20r_profile_basicinfo%20r_primary_current_experience%20r_mos
 t_recent_education


Required OAuth Scopes (Plus Tier):

      r_verify_details – Detailed verification metadata
      r_profile_basicinfo – Basic profile info

      r_primary_current_experience – Current job details
      r_most_recent_education – Education information



  ７ Note

  Request all scopes at once for the best user experience. See Implementation Guide for
  details.



Exchange Code for Access Token
After the member approves, LinkedIn redirects to your URI with an authorization code.
Exchange it for an access token:


 Bash
 curl -X POST 'https://www.linkedin.com/oauth/v2/accessToken' \
   -H 'Content-Type: application/x-www-form-urlencoded' \
   -d 'grant_type=authorization_code' \
   -d 'code={AUTHORIZATION_CODE}' \
   -d 'redirect_uri={YOUR_REDIRECT_URI}' \
   -d 'client_id={YOUR_CLIENT_ID}' \
   -d 'client_secret={YOUR_CLIENT_SECRET}'


Sample Response:


 JSON
 {
     "access_token": "AQWsGriMiJuFpzv7...",
   "expires_in": 5183999,
   "refresh_token": "AQVObXp9RNF9RuuN...",
   "scope":
 "r_verify_details,r_profile_basicinfo,r_primary_current_experience,r_most_recent_edu
 cation",
   "token_type": "Bearer"
 }



  ） Important

        Access tokens expire in 60 days
        Refresh tokens expire in 365 days
        Store both tokens securely and implement automatic refresh




Step 2: Call /identityMe API (3 minutes)
Get comprehensive member profile data including education and current position:


 Bash
 curl -X GET 'https://api.linkedin.com/rest/identityMe' \
   -H 'Authorization: Bearer {ACCESS_TOKEN}' \
   -H 'LinkedIn-Version: {LATEST_VERSION}'


Sample Response (Plus Tier):


 JSON

 {
     "id": "abc123",
     "lastRefreshedAt": 1760631246905,
     "basicInfo": {
       "firstName": {
         "localized": { "en_US": "John" },
         "preferredLocale": { "country": "US", "language": "en" }
       },
       "lastName": {
         "localized": { "en_US": "Doe" },
         "preferredLocale": { "country": "US", "language": "en" }
       },
       "primaryEmailAddress": "john.doe@example.com",
       "profileUrl": "https://www.linkedin.com/profile-thirdparty-redirect/...",
       "profilePicture": {
         "croppedImage": {
           "downloadUrl": "https://media.licdn.com/dms/image/...",
           "downloadUrlExpiresAt": 1763596800000
        }
       }
     },
     "primaryCurrentExperience": {
       "title": {
         "localized": { "en_US": "Software Engineer" },
         "preferredLocale": { "country": "US", "language": "en" }
       },
       "companyName": {
         "localized": { "en_US": "Tech Corp" },
         "preferredLocale": { "country": "US", "language": "en" }
       }
     },
     "mostRecentEducation": {
       "schoolName": {
         "localized": { "en_US": "University of Example" },
         "preferredLocale": { "country": "US", "language": "en" }
       },
       "degreeName": {
         "localized": { "en_US": "Bachelor of Science" },
         "preferredLocale": { "country": "US", "language": "en" }
       },
       "fieldOfStudy": {
         "localized": { "en_US": "Computer Science" },
         "preferredLocale": { "country": "US", "language": "en" }
       }
     }
 }



  ７ Note

  Plus tier returns additional fields: primaryCurrentExperience and mostRecentEducation . See
  /identityMe API Reference for complete schema.




Step 3: Call /verificationReport API (3 minutes)
Get detailed verification status with metadata:


 Bash
 curl -X GET 'https://api.linkedin.com/rest/verificationReport' \
   -H 'Authorization: Bearer {ACCESS_TOKEN}' \
   -H 'LinkedIn-Version: {LATEST_VERSION}'


Sample Response (Plus Tier):
 JSON

 {
     "id": "abc123",
     "verifications": ["IDENTITY", "WORKPLACE"],
     "identityVerification": {
       "verifiedName": {
         "firstName": {
           "localized": { "en_US": "John" },
           "preferredLocale": { "country": "US", "language": "en" }
         },
         "lastName": {
           "localized": { "en_US": "Doe" },
           "preferredLocale": { "country": "US", "language": "en" }
         }
       },
       "verifiedAt": 1698796800000
     },
     "workplaceVerification": {
       "organizationName": "Tech Corp",
       "organizationLogoUrl": "https://media.licdn.com/dms/image/...",
       "verificationMethod": "WORK_EMAIL",
       "verifiedAt": 1698796800000
     }
 }



  ７ Note

  Plus tier returns detailed metadata including verified names, timestamps, and verification
  methods. Development/Lite tiers only return verification categories.




Step 4: Call /validationStatus API (3 minutes)
Check data freshness for multiple members in bulk (Plus tier exclusive):


 Bash
 curl -X POST 'https://api.linkedin.com/rest/validationStatus' \
   -H 'Authorization: Bearer {ACCESS_TOKEN}' \
   -H 'LinkedIn-Version: {LATEST_VERSION}' \
   -H 'Content-Type: application/json' \
   -d '{
     "memberIds": ["abc123", "def456", "ghi789"]
   }'


Sample Response:
 JSON

 {
     "results": [
       {
         "memberId": "abc123",
         "status": "FRESH",
         "lastRefreshedAt": 1760631246905
       },
       {
         "memberId": "def456",
         "status": "STALE",
         "lastRefreshedAt": 1698796800000
       },
       {
         "memberId": "ghi789",
         "status": "FRESH",
         "lastRefreshedAt": 1760500000000
       }
     ]
 }



  ） Important

        2-legged OAuth - Uses client credentials (no member consent required)
        Batch limit - Up to 500 member IDs per request
        Use case - Check if cached data needs refreshing


See /validationStatus API Reference for complete documentation.




Step 5: Display Verification Data

Show Verification Badges
Follow branding guidelines to display verification badges:


 HTML
 <!-- Identity Verified -->
 <div class="verification-badge">
   <img src="identity-verified-badge.svg" alt="Identity Verified" />
   <span>Identity Verified</span>
 </div>

 <!-- Workplace Verified -->
 <div class="verification-badge">
  <img src="workplace-verified-badge.svg" alt="Workplace Verified" />
  <span>Workplace Verified at Tech Corp</span>
</div>




Display Profile Data

HTML
<div class="member-profile">
  <img src="{profilePicture.downloadUrl}" alt="{firstName} {lastName}" />
  <h2>{firstName} {lastName}</h2>
  <p>{primaryCurrentExperience.title} at {primaryCurrentExperience.companyName}</p>
  <p>Education: {mostRecentEducation.degreeName} from
{mostRecentEducation.schoolName}</p>
</div>




Best Practices

OAuth & Tokens
   ✅ Request all scopes at once (better UX)
   ✅ Store tokens encrypted at rest
   ✅ Implement automatic token refresh
   ✅ Use refresh tokens to keep data fresh


Data Freshness
   ✅ Use /validationStatus to check if data is stale
   ✅ Refresh stale data proactively
   ✅ Cache API responses appropriately
   ✅ See Data Freshness Guide


Security
   ✅ Enforce unique member ID validation
   ✅ Use HTTPS only
   ✅ Implement CSRF protection
   ✅ See Implementation Guide


Production Readiness
     ✅ Complete certification requirements
     ✅ Follow implementation guidelines
     ✅ Implement comprehensive error handling
     ✅ Monitor API usage and performance



Next Steps

Plus Tier Features
     Data Freshness - Keep member data up-to-date
     Certification - Production readiness requirements


Implementation Guide
     Implementation Guide - OAuth, tokens, testing, production best practices


API References
     /identityMe API - Profile details endpoint
     /verificationReport API - Verification details endpoint
     /validationStatus API - Bulk validation endpoint
     Authentication - OAuth details


Resources
     Branding Guidelines - Display badges correctly
     Common FAQ - Frequently asked questions
     Release Notes - API updates and changes




Troubleshooting

"Insufficient scope" Error
Cause: Missing required OAuth scopes

Solution:
   1. Verify all 4 scopes are requested: r_verify_details , r_profile_basicinfo ,
      r_primary_current_experience , r_most_recent_education

   2. Re-authorize the member with correct scopes
   3. Check token scope in OAuth response


"Product not assigned" Error
Cause: Plus tier not enabled for your application

Solution:

   1. Verify Plus tier approval with LinkedIn Business Development
   2. Check Developer Portal → Products tab shows "Plus Tier"
   3. Contact your LinkedIn partner manager


Missing Education or Job Data
Cause: Member hasn't added data to LinkedIn profile, or missing scopes

Solution:

   1. Check member's LinkedIn profile has education/job data
   2. Verify r_primary_current_experience and r_most_recent_education scopes granted
   3. Handle missing fields gracefully in your UI


Rate Limit Exceeded
Cause: Exceeded custom rate limits

Solution:

   1. Review your rate limit agreement
   2. Implement caching and optimize API calls
   3. Contact your LinkedIn partner manager to discuss limits



🎉 Congratulations! You're now using Verified on LinkedIn Plus tier with enterprise features.
Complete certification requirements before going to production.



 Last updated on 11/26/2025
Data Freshness
Learn how to keep member profile and verification data up-to-date using polling or push
notifications.


  ７ Note

  This guide focuses on refresh strategies for keeping data current and is only available for
  Plus tier. For initial data retrieval, call /verificationReport and /identityMe directly when
  the member authorizes your app.




Choose Your Refresh Method
                                                                                  ﾉ   Expand table


 Method                   Best For              When to Use

 Validation Status API    Bulk checks           Daily background jobs to check many members

 Push Notifications       Real-time updates     Event-driven notifications



  ） Important

  Critical: Regardless of how you detect data changes (polling via /validationStatus or
  push notifications), you must call the actual endpoints (/verificationReport and
  /identityMe) with the member's 3-legged OAuth access token to retrieve updated data.
  Status checks and notifications only indicate that changes exist—they don't contain the
  actual data.




Method 1: Validation Status API (Polling)

When to Use
     Performing bulk validation checks (up to 500 members)
     Running scheduled background jobs
     Checking if member data has been updated without member interaction
     Monitoring validation status across your entire user base
How It Works
   1. Check status (2-legged OAuth, no member consent needed):

           Call /validationStatus with up to 500 member id s
           Get status: VALID , INVALID , or VALID_WITH_UPDATES

   2. Refresh data (3-legged OAuth, member consent required):

           For members with VALID_WITH_UPDATES or INVALID status
           Call /verificationReport and /identityMe with member's access token
           Store updated data


   Tip

  Make sure you've stored the required fields listed in Critical Fields to Persist before
  implementing this method.



Recommended Polling Interval
Poll once per day (every 24 hours)

     Run during off-peak hours to minimize impact
     Batch requests (up to 500 members per call) to stay within rate limits
     Only call actual endpoints /verificationReport and /identityMe for members with status
     changes


Best Practices
     ✅ Run polling during off-peak hours
     ✅ Batch requests (up to 500 members per call)
     ✅ Only call actual endpoints for members with VALID_WITH_UPDATES or INVALID
     ✅ Implement exponential backoff for rate limit errors



Method 2: Push Notifications
Push notifications provide real-time updates when member data changes, eliminating the need
for constant polling.
  ７ Note

  To set up webhooks and enable push notifications for your application, please work with
  the Verified on LinkedIn Support team (voli-support@linkedin.com).



When to Use
     You need immediate notification when member data changes
     Event-driven architecture where you want to react to changes as they occur
     Reducing API calls compared to frequent polling


How It Works
   1. Register a webhook to receive push notifications
   2. Receive notifications when member verification or profile data changes
   3. Refresh data by calling /verificationReport and /identityMe with the member's 3-legged
     OAuth access token


  ） Important

  Push notifications indicate that changes exist—they do not contain the actual updated
  data. You must call the actual endpoints to retrieve the new data.



How to Register a Webhook?
Webhooks allow your application to receive real-time HTTP notifications when subscribed
events occur. Only applications with approved webhook use cases can register and receive
these notifications. LinkedIn sends notifications only to webhook endpoints that are properly
registered and successfully validated.



1. Register Your Webhook URL
     Open your application in the LinkedIn Developer Portal    .
     Navigate to the Webhooks tab.
     Click Create Webhook.
  ７ Note

  The Webhooks tab is visible only for applications that have been approved for webhook
  usage. Applications with the Verified on LinkedIn product will see the Webhooks tab in the
  Developer Portal.




2. Enter and Test Your Webhook Endpoint

When configuring your webhook in the LinkedIn Developer Portal, enter the HTTPS endpoint
where your application will receive LinkedIn push notifications.

Click Test to validate the webhook URL.



3. Choose Event Types
Select the events your application should be notified about. For Verified on LinkedIn
integrations, choose:

     Notifications of member verification or profile status change.

This ensures your webhook receives updates whenever a member’s verification or profile data
changes.
4. Validating the Webhook Endpoint
LinkedIn validates the ownership of a webhook URL before it can be registered by an
application. The validation flow leverages the application's clientSecret as the secret key along
with the universally-known HMACSHA256 algorithm to generate and validate the application's
response to a challenge code.

Once you save the URL and events, the webhook will appear with validation status and
notification status along with last validation time.




Event Payload
When member data changes, you'll receive a FEDERATED_MEMBER_DATA_STATUS_CHANGE event with
the following structure:
Example: Access Revoked
When a member revokes your application's access, verification and profile status fields are not
included:


 JSON
 {
      "id": "H6slYd_dso",
      "type": "FEDERATED_MEMBER_DATA_STATUS_CHANGE",
      "developerApplicationId": 220828831,
      "eventTimestamp": 1762378846790,
      "statusUpdate": {
        "isAccessRevoked": true
      }
 }




Example: Data Status Change
When member data changes but access is not revoked, the payload includes current status
values:


 JSON
 {
      "id": "K9mtZe_ftq",
      "type": "FEDERATED_MEMBER_DATA_STATUS_CHANGE",
      "developerApplicationId": 220828832,
      "eventTimestamp": 1762378856790,
      "statusUpdate": {
        "isAccessRevoked": false,
        "verificationStatus": {
          "identity": "INVALID",
          "workplace": "VALID_WITH_UPDATES"
        },
        "profileInformationStatus": "VALID"
      }
 }




Payload Fields

                                                                                    ﾉ   Expand table


 Field                     Type       Description

 id                        string     The member's unique identifier for your application
 Field                           Type         Description

 type                            string       Event type: FEDERATED_MEMBER_DATA_STATUS_CHANGE

 developerApplicationId          number       Your application's ID

 eventTimestamp                  number       Unix timestamp (milliseconds) when the change occurred

 statusUpdate                    object       Contains the status change details



Status Update Fields

                                                                                              ﾉ    Expand table


 Field                          Type        Description

 isAccessRevoked                boolean     true if the member revoked access to your application


 verificationStatus             object      Contains identity and/or workplace status (only present when
                                            isAccessRevoked is false )


 profileInformationStatus       string      Status of profile data: VALID or INVALID (only present when
                                            isAccessRevoked is false )




Status Values
For verificationStatus.identity and verificationStatus.workplace :


                                                                                              ﾉ    Expand table


 Status                  Meaning                                             Action Required

 VALID                   Data is current and accurate                        No action needed

 INVALID                 Data should be removed                              Call /verificationReport to refresh

 VALID_WITH_UPDATES      Data is valid but has newer verification            Optionally call /verificationReport
                         timestamp (Member re-verified)                      to get latest


For profileInformationStatus :


                                                                                              ﾉ    Expand table


 Status           Meaning                                                Action Required

 VALID            Profile data is current                                No action needed
Status           Meaning                                       Action Required

 INVALID         Profile data should be refreshed              Call /identityMe to refresh



 ７ Note

         If the member has no identity verification, verificationStatus.identity will not be
         present
         If the member has no workplace verification, verificationStatus.workplace will not
         be present
         If neither verification type exists, the entire verificationStatus object will not be
         present
         Similarly, profileInformationStatus is only included when profile data status is
         known




Handling Notifications
  1. Receive notification
  2. Check isAccessRevoked :

            If true → Remove member's data from your system
            If false → Continue to step 3

  3. Check each status field present in the payload:

            INVALID → Must refresh data

            VALID_WITH_UPDATES → Consider refreshing data

            VALID → No action needed


  4. Call /verificationReport and/or /identityMe with member's access token
  5. Update your stored data


Best Practices
     ✅ Validate the developerApplicationId matches your application
     ✅ Use eventTimestamp to ignore out-of-order or duplicate notifications
     ✅ Compare eventTimestamp with your stored lastRefreshedAt to avoid processing stale
     notifications
     ✅ Implement idempotent processing to handle potential duplicate deliveries
      ✅ When isAccessRevoked is true , delete or invalidate the member's stored data and
      tokens




Critical Fields to Persist
To effectively manage data freshness, you must persist these fields from the API response:


                                                                                     ﾉ   Expand table


 Field             Source                 Why It's Critical

 id                /verificationReport,   Required for /validationStatus checks and push
                   /identityMe            notifications. Uniquely identifies the member for your
                                          application.

 refresh_token     OAuth token response   Required to obtain new access tokens without member re-
                                          authorization. Essential for refreshing data when member is
                                          not actively using your app.

 lastRefreshedAt   /verificationReport,   Timestamp of when data was last updated. Use to ignore
                   /identityMe            stale push notifications and avoid unnecessary API calls.



  ２ Warning

  The userId field will be deprecated in future API versions. Use the id field as the standard
  identifier (available since version 202510). Only persist userId if you are migrating from
  an older API version and need temporary backward compatibility.



Storage Best Practices
      ✅ Encrypt and store tokens
      ✅ Store in secure backend database with proper access controls
      ✅ Index the id field for fast lookups
      ✅ Implement token rotation and secure deletion policies
      ✅ Never store tokens in client-side storage (cookies, localStorage)



Related Resources
      /identityMe API – Profile details endpoint
     /verificationReport API – Verification details endpoint
     /validationStatus API – Bulk validation endpoint
     Webhooks Guide – Learn how to register and validate webhook endpoints for receiving
     real-time notifications
     Quickstart Guide – Get started in 5 minutes
     FAQ – Troubleshooting and answers



Last updated on 12/10/2025
Certification Checklist
All partners must complete this certification process to be approved for production access. The
checklist covers OAuth integration, verification workflows, error handling, and LinkedIn policy
compliance.

You must demonstrate and document completion of each requirement with screenshots, logs,
or product flow explanations as appropriate.



Certification Areas
The checklist is divided into the following three categories:



Integration Requirements
                                                                                        ﾉ   Expand table


 ID    Requirement        Expectations

 SL-   OAuth 2.0          Implement OAuth 2.0 using the appropriate scopes for your use case. Only
 001   Integration with   request the scopes that are required, such as: r_profile_basicinfo ,
       Correct Scopes     r_most_recent_education , r_primary_current_experience , and
                          r_verify_details . Requesting additional scopes may result in unnecessarily
                          large responses or data beyond the partner’s intended use case, leading to
                          integration mismatches or unused information.

 SL-   Token Expiration   Reuse valid access tokens when available. If the access token has expired, use
 002   & Management       the refresh token to obtain a new one. If the refresh token is also expired or
                          invalid, re-trigger the OAuth flow with the member to obtain a new access
                          token.

 SL-   Breaking Change    Confirm that you have read and agreed to LinkedIn’s breaking change policy.
 003   Policy

 SL-   Handle API         Capture version expiry errors, monitor 426 responses, track X-LI-UUID header,
 004   Version Expiry     and include the LinkedIn-Version header in all requests.




Verification Workflow
                                                                                        ﾉ   Expand table
ID    Requirement               Expectations

SL-   Full Verification Flow    Demonstrate end-to-end flow for a user with no pre-existing
005   (New User)                verifications: from CTA → LinkedIn verification → back to platform →
                                display of badge and timestamp.

SL-   Verification Badge        Use “Verified on LinkedIn” text, proper branding, link to LinkedIn
006   Implementation            profile, and display of category & timestamp.

SL-   Use of /identityMe API    Fetch and use basic member info; explain how this is used in your
007                             platform.

SL-   Flow for Pre-Verified     Demonstrate flows for users with: only identity, only workplace, and
008   Users                     both. Support case-specific verification requests.

SL-   Incomplete or Cancelled   Handle user cancellations or consent rejections gracefully. Show error
009   Flow Handling             handling when access is revoked or OAuth fails.

SL-   Error Logging & UUID      Demonstrate error logging with request/response headers, especially
010   Tracking                  X-LI-UUID .




Integration Compliance
                                                                                        ﾉ   Expand table


ID    Requirement                Expectations

SL-   Pass LinkedIn InfoSec      Application must pass LinkedIn’s security assessment process.
011   Review

SL-   Developer App Admin        Ensure admins are listed in the developer app and kept up to date.
012   Management

SL-   Business Email DL Setup    Create a distribution list (DL) with correct owners and register it as
013                              the business email in the LinkedIn Developer Portal.

SL-   Support Routing Post-GA    Route all post-go-live support queries to LinkedIn Business
014                              Development team.

SL-   Subscribe to API Status    Subscribe to LinkedIn API Status     for real-time incident updates.
015   Page

SL-   Monitor API Release        Regularly review LinkedIn’s API release documentation for changes.
016   Updates




Data Use & Retention Guidelines
If LinkedIn has granted you access to the Verified on LinkedIn Plus Program, it will appear in
the list of products that your application has access to on the LinkedIn developer portal. Please
note that access to certain data fields may be restricted.

Consult your Verified on LinkedIn API Agreement for other restrictions, conditions, and data
deletion obligations relating to this data. For example, the Verified on LinkedIn Agreement
requires that you obtain an authenticated Member’s consent before storing their verification
data. If there is any conflict between these requirements and the requirements in your
Agreement, the requirements that are more restrictive or more protective of the data apply.
Similarly, if a given data field is encompassed by two or more of the following requirements,
the shortest storage/caching duration shall apply.

LinkedIn reserves the right to update these requirements at any time by posting changes on
our developer documentation, and it is your responsibility to review and ensure your
integration remains compliant with the most current requirements. Partners are expected to
make necessary updates to their systems and processes in a timely manner to remain in good
standing.

The following requirements do not apply to data that is independently provided to you by your
clients and not retrieved via the Verified on LinkedIn API.


API Guides
     Verification Report API Guide
     Identity Me API Guide
     Validation Status API Guide
     OAuth Authorization Code Flow Guide


Integration Resources
     Quickstart Guide
     OAuth 2.0 Authentication
     Implementation Guidelines
     Data Freshness
     Validation Status API


Developer Resources
     LinkedIn Developer Portal
     LinkedIn API Status Page
Last updated on 11/26/2025
Implementation Guide
Comprehensive guide covering OAuth implementation, testing strategies, and production
deployment best practices. These guidelines apply to all Verified on LinkedIn tiers
(Development, Lite, and Plus).




OAuth Scope Management

Request All Scopes at Once (Recommended)
To provide the best user experience and avoid multiple authorization prompts, request all
required OAuth scopes in a single authorization request.

Available Scopes by Tier:


                                                                                          ﾉ     Expand table


 Scope                           Purpose                            API                       Available In

 r_profile_basicinfo             Basic profile information          /identityMe               All tiers
                                 (name, email, profile URL,
                                 picture)

 r_verify                        Verification categories (not       /verificationReport       Development,
                                 detailed metadata)                                           Lite

 r_verify_details                Detailed verification status and   /verificationReport       Plus only
                                 metadata

 r_most_recent_education         Most recent education details      /identityMe               Plus only

 r_primary_current_experience    Current workplace information      /identityMe               Plus only




Authorization URL Examples
When redirecting members to LinkedIn for authorization, include all required scopes in the
authorization URL, here are the example redirection URLs for different tiers:

Development/Lite Tier:




 https://www.linkedin.com/oauth/v2/authorization?
   response_type=code&
   client_id={YOUR_CLIENT_ID}&
   redirect_uri={YOUR_REDIRECT_URI}&
   state={RANDOM_STATE}&
   scope=r_profile_basicinfo%20r_verify


Plus Tier:




 https://www.linkedin.com/oauth/v2/authorization?
   response_type=code&
   client_id={YOUR_CLIENT_ID}&
   redirect_uri={YOUR_REDIRECT_URI}&
   state={RANDOM_STATE}&

 scope=r_verify_details%20r_profile_basicinfo%20r_most_recent_education%20r_primary_c
 urrent_experience


Key Points:

     Scopes are space-separated (URL-encoded as %20 )
     Request all scopes upfront to avoid re-authorization
     Member grants consent once for all requested permissions
     Reduces friction in the user experience


Why Request All Scopes Together?
✅ Single consent flow - Member authorizes once instead of multiple times
✅ Complete data access - Get all profile and verification data in one session
✅ Better UX - Avoid interrupting member with additional authorization requests
✅ Simplified implementation - No need to manage partial authorization states



User ID Management

ID Uniqueness Validation (Critical)
Requirement: You must validate that each id is unique in your system.

Why: Failing to validate uniqueness allows a single LinkedIn account to verify multiple accounts
on your platform, creating a security vulnerability.


  ７ Note
  Always use the id field (available since version 202510). The userId field will be
  deprecated in future versions and should only be used for temporary backward
  compatibility during migration from older API versions.



Best Practices
     ✅ Enforce uniqueness at the database level (UNIQUE constraint)
     ✅ Check for existing LinkedIn ID before saving new verification
     ✅ Log security alerts when duplicate attempts are detected
     ✅ Display clear error messages to members
     ✅ Provide support contact for legitimate edge cases



Token Storage
Requirement: You must securely store OAuth access tokens and refresh tokens with
encryption.

Why: Storing refresh tokens is necessary to generate new access tokens when needed to
refresh member data without requiring the member to re-authorize. This enables you to keep
member profile and verification information up-to-date through background processes.


Storage Best Practices
     ✅ Encrypt tokens using AES-256-GCM or equivalent
     ✅ Store in secure backend database with proper access controls
     ✅ Implement token rotation and secure deletion policies
     ✅ Never store tokens in client-side storage (cookies, localStorage, sessionStorage)
     ✅ Log access to tokens for audit purposes



Testing Your Integration

Basic Test Flow
1. OAuth Flow Testing

     ✅ Test successful authorization
     ✅ Test member denies authorization (handle gracefully)
     ✅ Test token expiry and refresh
     ✅ Validate state parameter (CSRF protection)
2. API Testing

     ✅ Call /identityMe with valid token
     ✅ Call /verificationReport with valid token
     ✅ Verify response fields (id, basicInfo, verifications)
     ✅ Handle missing optional fields (email, profile picture)
3. Error Handling

     ✅ Test with invalid token (401 error)
     ✅ Test with insufficient scopes (403 error)
     ✅ Handle API errors gracefully
     ✅ Log errors for debugging

Test Variations
Verification Cases:

     Fully verified (IDENTITY + WORKPLACE)
     Partially verified (IDENTITY only or WORKPLACE only)
     Unverified (empty verifications array)
     Redirect Member to LinkedIn verification URL to add more verifications
     Handle callback to Partner website on successful verification completion

Edge Cases:

     Missing email address
     Missing profile picture
     Non-English names and locales, Special characters in names
     Member has no verifications and not eligible for any verifications as well




Production Deployment

Pre-Production Checklist
Security:

     ✅ Tokens encrypted at rest
     ✅ Client secret in environment variables
     ✅ HTTPS only for all API calls
     ✅ State parameter implemented (CSRF protection)
     ✅ Token refresh automated

API Integration:

     ✅ Error handling for all API responses
     ✅ Timeout handling (5s timeout for all endpoints and 30s timeout for /validationStatus)
     ✅ Logging for errors and key events
Data Handling:

     ✅ Member ID uniqueness enforced based on your business use case
     ✅ Handle missing optional fields gracefully
     ✅ Check image URL expiry before display

User Experience:

     ✅ Follow branding guidelines
     ✅ Handle unverified members gracefully
     ✅ Clear success and error messaging
     ✅ Mobile responsive design



Related Resources

Tier-Specific Guides
     10-min Development Tier Quickstart – Get started with testing
     10-min Lite Tier Quickstart – Production-ready integration
     10-min Plus Tier Quickstart – Enterprise features


OAuth Guides
     Authorization Code Flow – OAuth 2.0 3-legged authentication
     Client Credentials Flow – OAuth 2.0 2-legged authentication (Plus tier only)


API References
     /identityMe API – Profile details endpoint
     /verificationReport API – Verification details endpoint
     /validationStatus API – Bulk validation (Plus tier only)
Plus Tier Features
     Data Freshness – Keep member data up-to-date (Plus only)
     Certification – Production readiness requirements (Plus only)



Last updated on 11/26/2025
Authentication
Verified on LinkedIn APIs use OAuth 2.0 for authentication. The authentication method
depends on which API you're calling.



OAuth Flow by API
                                                                                     ﾉ    Expand table


 API                             OAuth Type            Member Consent                    Tiers

 /identityMe                     3-legged              ✅ Required                        All tiers

 /verificationReport             3-legged              ✅ Required                        All tiers

 /validationStatus               2-legged              ❌ Not required                    Plus only




3-Legged OAuth (Authorization Code Flow)
Used for /identityMe and /verificationReport APIs. Requires member consent and
authorization.


Quick Overview
   1. Redirect member to LinkedIn for authorization
   2. Member grants permission to your app
   3. LinkedIn redirects back with authorization code
   4. Exchange code for access token
   5. Call APIs with the access token


Required OAuth Scopes by Tier

                                                                                     ﾉ    Expand table


 Scope                        Development     Lite   Plus   Purpose

 r_profile_basicinfo          ✅               ✅      ✅      Basic profile info (name, email, photo)

 r_verify                     ✅               ✅      ❌      Verification categories only (Dev & Lite)
 Scope                          Development   Lite    Plus   Purpose

 r_verify_details               ❌             ❌       ✅      Detailed verification metadata (Plus only)
                                                             + Verification categories

 r_primary_current_experience   ❌             ❌       ✅      Current job details (Plus only)

 r_most_recent_education        ❌             ❌       ✅      Education info (Plus only)



  ） Important

  Key Difference: r_verify returns only verification categories (e.g., ["IDENTITY",
  "WORKPLACE"] ), while r_verify_details returns full metadata including verified names,

  timestamps, methods, and organization details.



Token Characteristics
     Access token lifetime: 60 days
     Refresh token lifetime: 1 year
     Refresh tokens: Yes, included in response
     Member consent: Required once (unless scopes change)


Complete Guide
For detailed implementation, see:

     Authorization Code Flow Guide – Complete 3-legged OAuth walkthrough
     Refresh Tokens Guide – Token refresh implementation




2-Legged OAuth (Client Credentials Flow)
Used for /validationStatus API (Plus tier only). No member consent required.


Quick Overview
   1. Request access token using client credentials
   2. Call API with the access token
   3. Token expires in 30 minutes – request new token as needed
Required OAuth Scope
     r_validation_status – Bulk validation checks (Plus tier only)



Token Characteristics
     Access token lifetime: 30 minutes
     Refresh tokens: No, request new token after expiry
     Member consent: Not required


Complete Guide
For detailed implementation, see:

     Client Credentials Flow Guide – Complete 2-legged OAuth walkthrough




Getting Started by Tier

Development Tier
     Scopes: r_profile_basicinfo , r_verify
     Test with admin accounts only
     See Quickstart Guide for setup instructions


Lite Tier
     Scopes: r_profile_basicinfo , r_verify (same as Development)
     Access all member data (with consent)
     See Upgrade to Lite Tier for setup instructions


Plus Tier
     Scopes: r_verify_details , r_profile_basicinfo , r_primary_current_experience ,
     r_most_recent_education

     Access to 2-legged OAuth for bulk validation
     See Implementation Guide for setup instructions
Common Questions

Do tokens work across tier upgrades?
Yes! When you upgrade from Development to Lite or Lite to Plus:

     Existing access tokens remain valid
     Members don't need to re-authorize (unless you add new scopes)
     Only request new consent if adding scopes


How do I add more scopes?
If you need additional OAuth scopes (e.g., upgrading to Plus tier):

   1. Update your authorization URL with new scopes
   2. Ask member to re-authorize
   3. New tokens will include additional scopes


What happens when tokens expire?
3-legged OAuth (access token):

     Use refresh token to get new access token
     No member interaction required

Example: Refresh Token Request


 Bash
 curl -X POST "https://www.linkedin.com/oauth/v2/accessToken" \
   -H "Content-Type: application/x-www-form-urlencoded" \
   --data-urlencode 'grant_type=refresh_token' \
   --data-urlencode 'refresh_token=<REFRESH_TOKEN>' \
   --data-urlencode 'client_id=<CLIENT_ID>' \
   --data-urlencode 'client_secret=<CLIENT_SECRET>'


     See Refresh Tokens Guide

2-legged OAuth:

     Request new token using client credentials
     No user interaction involved
     Happens automatically in 30 minutes
Best Practices
✅ Store tokens securely – Encrypt at rest, never expose in client-side code
✅ Use refresh tokens – Don't make users re-authenticate every 60 days
✅ Request minimum scopes – Only request what you need
✅ Handle token expiry gracefully – Implement automatic refresh logic
✅ Validate redirect URIs – Must match exactly with Developer Portal settings



Related Resources

Authentication Guides
     Authorization Code Flow – 3-legged OAuth
     Client Credentials Flow – 2-legged OAuth
     Refresh Tokens – Token refresh
     Developer Portal Tools – Token management


API Reference
     Profile Details API – Requires 3-legged OAuth
     Verification Report API – Requires 3-legged OAuth
     Validation Status API – Requires 2-legged OAuth (Plus only)


Getting Started
     Quickstart Guide – Get started in 5 minutes
     Implementation Guide – OAuth best practices



Last updated on 11/26/2025
Profile Details API (/identityMe)
The Profile Details API endpoint ( /identityMe ) retrieves LinkedIn member profile information
including name, email, profile photo, and profile URL. Plus tier also provides access to current
job and education details.


  ７ Note

  Tier Availability: Development ✅ | Lite ✅ | Plus ✅

  All tiers can access this API. Plus tier receives additional fields (education and current
  position).




Overview
Key Features:

     Retrieve member's basic profile (name, email, photo, profile URL)
     Access most recent education details (Plus tier only)
     Get current workplace information (Plus tier only)
     OAuth: 3-legged (member consent required)
     Version: 202510.03 (Plus tier) / Check Release Notes (Dev/Lite tier)


  ） Important

  Education data comes from this API using the r_most_recent_education OAuth scope
  (Plus tier only). Education is not included in the /verificationReport API.




Rate Limits
                                                                                    ﾉ   Expand table


 Limit Type          Development   Lite        Plus     Description

 Application-level   5,000/day     5,000/day   Custom   Maximum API calls per day across all users

 Member-level        500/day       500/day     Custom   Maximum calls per individual member per day



  ７ Note
 Plus tier rate limits are customized based on partnership agreement.




Endpoint Details
HTTP
GET https://api.linkedin.com/rest/identityMe




Required Headers

                                                                                   ﾉ    Expand table


Header                     Value                      Description

LinkedIn-Version           {LATEST_VERSION}           API version (see Release Notes)




Required OAuth Scopes

                                                                                   ﾉ    Expand table


Scope                          Development    Lite          Plus         Purpose

r_profile_basicinfo            ✅ Available    ✅             ✅            Basic profile info (name,
                                              Available     Available    email, photo, profile URL)

r_most_recent_education        ❌ Not          ❌ Not         ✅            Most recent education
                               available      available     Available    details

r_primary_current_experience   ❌ Not          ❌ Not         ✅            Current workplace
                               available      available     Available    information



 ２ Warning

 Development Tier Limitation: You can only access data for LinkedIn accounts that are
 administrators of your developer application. This tier is for testing only.

 For production use, upgrade to Lite tier.
Response Fields by Tier

Common Fields (All Tiers)
These fields are available in Development, Lite, and Plus tiers:


                                                                                      ﾉ   Expand table


 Field                           Type                Always       Description
                                                     Returned

 id                              string              ✅ Yes        Unique identifier for the member
                                                                  scoped to your application

 lastRefreshedAt                 timestamp           ✅ Yes        When profile data was pulled (current
                                                                  timestamp in milliseconds since
                                                                  epoch), useful to ignore older
                                                                  updates when subscribed to push
                                                                  notifications

 basicInfo                       object              ✅ Yes        Contains name, email, profile URL,
                                                                  and profile picture

 basicInfo.firstName             MultiLocaleString   ✅ Yes        Member's first name (localized)

 basicInfo.lastName              MultiLocaleString   ✅ Yes        Member's last name (localized)

 basicInfo.primaryEmailAddress   string              If present   Member's primary email address

 basicInfo.profileUrl            string              ✅ Yes        Public LinkedIn profile URL

 basicInfo.profilePicture        object              If present   Profile picture with cropped image
                                                                  URL and expiry



Plus Tier Only Fields

  ） Important

  Plus tier only: The following fields require Plus tier access and appropriate OAuth scopes.




Education Fields (requires r_most_recent_education scope)

                                                                                      ﾉ   Expand table
Field                               Type                 Always               Description
                                                         Returned

 mostRecentEducation                object               If present           Most recent education details

 mostRecentEducation.schoolName     MultiLocaleString    If present           Name of school or university

 mostRecentEducation.degreeName     MultiLocaleString    If present           Degree name (e.g., "Bachelor of
                                                                              Science")

 mostRecentEducation.schoolLogo     object               If present           School/university logo image




Experience Fields (requires r_primary_current_experience scope)

                                                                                              ﾉ   Expand table


Field                                        Type                Always               Description
                                                                 Returned

 primaryCurrentPosition                      object              If present           Current job information

 primaryCurrentPosition.title                MultiLocaleString   If present           Member's current job
                                                                                      title

 primaryCurrentPosition.companyName          MultiLocaleString   If present           Company name

 primaryCurrentPosition.companyPageUrl       string              If present           LinkedIn company page
                                                                                      URL

 primaryCurrentPosition.companyLogo          object              If present           Company logo image

 primaryCurrentPosition.startedOn            object              If present           Start date (month and
                                                                                      year)



 ７ Note

 Plus tier fields may be absent if:

        Member hasn't added education/experience to their LinkedIn profile
        Required OAuth scopes were not requested during authorization
        Member denied consent for specific scopes




Example Requests and Responses
Example 1: Development & Lite Tier Response
Request:


 Bash
 curl -X GET 'https://api.linkedin.com/rest/identityMe' \
   -H 'Authorization: Bearer {ACCESS_TOKEN}' \
   -H 'LinkedIn-Version: {LATEST_VERSION}'


Response (Development/Lite Tier):


 JSON

 {
   "lastRefreshedAt": 1760631246905,
   "id": "1n23dEFSmS",
   "basicInfo": {
     "firstName": {
       "localized": {
         "en_US": "John"
       },
       "preferredLocale": {
         "country": "US",
         "language": "en"
       }
     },
     "lastName": {
       "localized": {
         "en_US": "Doe"
       },
       "preferredLocale": {
         "country": "US",
         "language": "en"
       }
     },
     "primaryEmailAddress": "john.doe@example.com",
     "profileUrl": "https://www.linkedin.com/profile-thirdparty-redirect/example-
 profile-url",
     "profilePicture": {
       "croppedImage": {
         "downloadUrl": "https://media.licdn.com/dms/image/v2/example/profile-pic",
         "downloadUrlExpiresAt": 1763596800000
       }
     }
   }
 }




Example 2: Plus Tier Response (Full Profile)
Request:


 Bash
 curl -X GET 'https://api.linkedin.com/rest/identityMe' \
   -H 'Authorization: Bearer {ACCESS_TOKEN}' \
   -H 'LinkedIn-Version: 202510.03'


Response (Plus Tier with Education & Current Position):


 JSON
 {
   "lastRefreshedAt": 1761512274175,
   "id": "abc123xyz",
   "basicInfo": {
     "firstName": {
       "localized": {
         "en_US": "John"
       },
       "preferredLocale": {
         "country": "US",
         "language": "en"
       }
     },
     "lastName": {
       "localized": {
         "en_US": "Doe"
       },
       "preferredLocale": {
         "country": "US",
         "language": "en"
       }
     },
     "primaryEmailAddress": "john.doe@example.com",
     "profileUrl": "https://www.linkedin.com/profile-thirdparty-redirect/example-
 profile-url",
     "profilePicture": {
       "croppedImage": {
         "downloadUrl": "https://media.licdn.com/dms/image/v2/example/profile-pic",
         "downloadUrlExpiresAt": 1762992000000
       }
     }
   },
   "mostRecentEducation": {
     "schoolName": {
       "localized": {
         "en_US": "Stanford University"
       },
       "preferredLocale": {
         "country": "US",
         "language": "en"
       }
      },
      "schoolLogo": {
        "originalImage": {
          "downloadUrl": "https://media.licdn.com/dms/image/v2/example/company-logo",
          "downloadUrlExpiresAt": 1762992000000
        }
      },
      "degreeName": {
        "localized": {
          "en_US": "Master of Science in Computer Science"
        },
        "preferredLocale": {
          "country": "US",
          "language": "en"
        }
      }
    },
    "primaryCurrentPosition": {
      "title": {
        "localized": {
          "en_US": "Senior Software Engineer"
        },
        "preferredLocale": {
          "country": "US",
          "language": "en"
        }
      },
      "companyName": {
        "localized": {
          "en_US": "LinkedIn"
        },
        "preferredLocale": {
          "country": "US",
          "language": "en"
        }
      },
      "companyPageUrl": "https://www.linkedin.com/company/1234",
      "companyLogo": {
        "originalImage": {
          "downloadUrl": "https://media.licdn.com/dms/image/v2/example/company-logo",
          "downloadUrlExpiresAt": 1762992000000
        }
      },
      "startedOn": {
        "month": 1,
        "year": 2022
      }
    }
}




Detailed Field Schemas
MultiLocaleString Format
Used for fields like firstName , lastName , schoolName , degreeName , title , and companyName :


 JSON
 {
     "localized": {
       "en_US": "Example Text"
     },
     "preferredLocale": {
       "country": "US",
       "language": "en"
     }
 }




Image Objects (Profile Picture, School Logo, Company Logo)
Profile Picture:


 JSON
 {
     "croppedImage": {
       "downloadUrl": "https://media.licdn.com/dms/image/v2/...",
       "downloadUrlExpiresAt": 1762992000000
     }
 }


School/Company Logo:


 JSON
 {
     "originalImage": {
       "downloadUrl": "https://media.licdn.com/dms/image/v2/...",
       "downloadUrlExpiresAt": 1762992000000
     }
 }



  ２ Warning

  Image URLs expire. Always check downloadUrlExpiresAt and re-fetch the API response if
  the URL has expired.
Start Date Object

JSON
{
    "month": 1,
    "year": 2022
}


      month : Integer from 1-12

      year : Four-digit year




Error Handling

Common API Errors

                                                                                         ﾉ   Expand table


HTTP        Error                      Cause                           Solution
Status

400         Bad Request                Invalid parameters or           Verify request URL, parameters,
                                       malformed request               and headers

401         Unauthorized               Invalid or expired access       Refresh the access token and retry
                                       token

401         Failed to get member ID    Invalid member information      Re-authenticate member to get
                                       in token                        new access token

401         Failed to get developer    Invalid developer application   Verify access token; re-
            application urn            info in token                   authenticate if needed

403         Forbidden                  Missing required OAuth          Ensure r_profile_basicinfo scope
                                       scope                           is authorized

403         No valid API product       Product not enabled in          Add "Verified on LinkedIn" product
            assigned                   Developer Portal                to your app

403         Insufficient permissions   Development tier: Non-          Use admin member token or
            (admin required)           admin member                    upgrade to Lite tier

403         Insufficient permissions   Missing required OAuth          Request required scopes during
                                       scopes                          authorization
 HTTP      Error                   Cause                        Solution
 Status

 404       Not Found               Member not found or          Verify the member's LinkedIn
                                   deleted                      account status

 426       Upgrade Required        Deprecated API version       Update LinkedIn-Version header
                                                                to latest version

 429       Too Many Requests       Rate limit exceeded          Retry after delay specified in
                                                                Retry-After header


 500       Internal Server Error   Temporary LinkedIn service   Retry with exponential backoff;
                                   issue or unexpected error    contact support if persists


For additional error handling guidance, see the LinkedIn API Error Handling Guide.




Best Practices

For All Tiers
✅ Always use LinkedIn-Version header to ensure API compatibility
✅ Cache responses temporarily to minimize redundant API calls
✅ Validate member ID uniqueness in your system (critical for data integrity)
✅ Handle missing optional fields gracefully (email, profile picture may be absent)
✅ Check image URL expiration before displaying cached images
✅ Combine with /verificationReport for complete verification context


For Development Tier
⚠️Remember: Only admin accounts can be accessed
💡 Test thoroughly before requesting Lite tier upgrade
💡 Use for prototyping OAuth flow and UI integration


For Plus Tier
✅ Request only needed scopes - Don't request education/experience if not required
✅ Implement data freshness strategies - Use /validationStatus API to check if data needs
refresh
✅ Handle missing Plus fields - Members may not have education/experience on profile
Use Cases

All Tiers
   Display member's name and profile picture in your application
   Associate LinkedIn identity with your platform's user account
   Show "Verified on LinkedIn" badges with member context
   Personalize onboarding flows


Plus Tier Additional Use Cases
   Display current job title and company in member profiles
   Show education credentials for professional verification
   Build trust scores based on professional background
   Pre-fill job application forms with LinkedIn data




Related Resources

APIs
   Verification Report API – Get verification details (identity & workplace)
   Validation Status API – Bulk validation checks (Plus tier only)


Guides
   Quickstart Guide – Get started with the API
   Upgrade to Lite Tier – Move to production
   Implementation Guide – Best practices
   Data Freshness Strategies – Keep data current (Plus tier)
   Certification Requirements – Production readiness (Plus tier)


Authentication
   Authorization Code Flow – OAuth 2.0 3-legged authentication


Other Resources
   FAQ – Troubleshooting and answers
     Release Notes – API updates and current versions
     Overview – Product overview and tier comparison



Last updated on 11/26/2025
Verification Report API
(/verificationReport)
The Verification Report API allows you to retrieve verification information for LinkedIn
members, including verification categories (e.g., IDENTITY , WORKPLACE ), detailed metadata, and
verification URLs for eligible members.


  ７ Note

  Tier Availability: Development ✅ | Lite ✅ | Plus ✅

  All tiers can access this API. Plus tier receives additional detailed metadata (verified names,
  timestamps, methods, organization info).




Overview
Key Features:

     Check member's verification status (identity and workplace)
     Get detailed verification metadata (Plus tier only)
     Generate verification URLs for unverified members
     OAuth: 3-legged (member consent required)
     Version: 202510 (Plus tier) / Check Release Notes (Dev/Lite tier)


Verification Categories

                                                                                  ﾉ   Expand table


 Category          Description                                                     Available In

 IDENTITY          Government ID-based verification                                All tiers

 WORKPLACE         Work affiliation verification (email or Microsoft Entra)        All tiers




Rate Limits
                                                                                  ﾉ   Expand table
Limit Type          Development    Lite          Plus     Description

Application-level   5,000/day      5,000/day     Custom   Maximum API calls per day across all users

Member-level        500/day        500/day       Custom   Maximum calls per individual member per day



 ７ Note

 Plus tier rate limits are customized based on partnership agreement.




Endpoint Details
HTTP

GET https://api.linkedin.com/rest/verificationReport




Required Headers

                                                                                      ﾉ   Expand table


Header                Value                      Description

Authorization         Bearer {ACCESS_TOKEN}      OAuth 2.0 access token authorized by the member

LinkedIn-Version      {LATEST_VERSION}           API version (see Release Notes)




Required OAuth Scope

                                                                                      ﾉ   Expand table


Scope                 Development         Lite            Plus            Purpose

r_verify_details      ✅ Required          ✅ Required      ✅ Required      Access to verification data



 ７ Note

 Some older implementations may use r_verify scope. Both are accepted, but
 r_verify_details is the current standard.
  ２ Warning

  Development Tier Limitation: You can only access data for LinkedIn accounts that are
  administrators of your developer application. This tier is for testing only.

  For production use, upgrade to Lite tier.



Query Parameters

                                                                                       ﾉ    Expand table


 Parameter              Type     Required   Description

 verificationCriteria   string   Optional   Specifies verification categories for URL generation. Can be
                                            repeated for multiple values: IDENTITY , WORKPLACE



  ） Important

  How verificationCriteria works:

        Does NOT filter response – Always returns ALL completed verifications
        Controls URL generation – Only generates URL for requested criteria
        Multiple values – Repeat parameter: ?
        verificationCriteria=IDENTITY&verificationCriteria=WORKPLACE

        DO NOT use comma-separated – Will return 400 Bad Request error


Examples:


 Bash
 # Request both verifications
 GET /verificationReport?verificationCriteria=IDENTITY&verificationCriteria=WORKPLACE

 # Request only identity
 GET /verificationReport?verificationCriteria=IDENTITY

 # No criteria (returns URL for any eligible verification)
 GET /verificationReport




Response Fields by Tier
Common Fields (All Tiers)
These fields are available in Development, Lite, and Plus tiers:


                                                                                             ﾉ   Expand table


 Field             Type         Always           Description
                                Returned

 id                string       ✅                Unique identifier for member scoped to your application

 verifications     array of     ✅                Completed verification categories (e.g., ["IDENTITY",
                   strings                       "WORKPLACE"] ). Empty array if no verifications.


 verificationUrl   string       ⚠️Optional       URL to LinkedIn verification flow. Present only if member
                                                 is eligible for additional verifications.



Development & Lite Tier Response
Development and Lite tiers receive only the basic verification categories without detailed
metadata.


Plus Tier Additional Fields

  ） Important

  Plus tier only: The following fields provide detailed verification metadata and require Plus
  tier access.



                                                                                             ﾉ   Expand table


 Field             Type               Description

 userId            string             Legacy identifier format (being deprecated - use id instead)

 lastRefreshedAt   timestamp          When verification data was last refreshed (milliseconds since epoch)

 verifiedDetails   array of objects   Detailed verification metadata for each completed verification




verifiedDetails Array (Plus Only)

Each object represents a completed verification with detailed metadata.
Common Fields:


                                                                                     ﾉ    Expand table


 Field                Type        Description

 category             string      Verification category: IDENTITY or WORKPLACE

 lastVerifiedAt       timestamp   When verification was completed (milliseconds since epoch)


IDENTITY Verification Fields:


                                                                                     ﾉ    Expand table


 Field                            Type       Description

 verifiedName                     object     Legal name from government ID

 verifiedName.firstName           string     Verified first name (uppercase)

 verifiedName.middleName          string     Verified middle name (optional, uppercase)

 verifiedName.lastName            string     Verified last name (uppercase)


WORKPLACE Verification Fields:


                                                                                     ﾉ    Expand table


 Field                              Type         Description

 verificationMethod                 string        EMAIL_ADDRESS or MICROSOFT_ENTRA


 organizationInfo                   object       Company information

 organizationInfo.name              string       Company name

 organizationInfo.url               string       LinkedIn company page URL




Example Requests and Responses

Example 1: Development/Lite Tier - Fully Verified Member
Member has completed both verifications. No verificationUrl in response.

Request:
 Bash
 curl -X GET 'https://api.linkedin.com/rest/verificationReport' \
   -H 'Authorization: Bearer {ACCESS_TOKEN}' \
   -H 'LinkedIn-Version: {LATEST_VERSION}'


Response (Development/Lite Tier):


 JSON
 {
     "verifications": ["IDENTITY", "WORKPLACE"],
     "id": "Yw-zU_kyua"
 }




Example 2: Development/Lite Tier - Unverified Member
Member has no verifications but is eligible. Response includes verificationUrl .

Request:


 Bash
 curl -X GET 'https://api.linkedin.com/rest/verificationReport?
 verificationCriteria=IDENTITY&verificationCriteria=WORKPLACE' \
   -H 'Authorization: Bearer {ACCESS_TOKEN}' \
   -H 'LinkedIn-Version: {LATEST_VERSION}'


Response (Development/Lite Tier):


 JSON
 {
   "verifications": [],
   "id": "Yw-zU_kyua",
   "verificationUrl": "https://www.linkedin.com/trust/verification?
 isDeeplinkToCCT=true&verificationUrl=..."
 }




Example 3: Plus Tier - Fully Verified Member with Metadata
Member has completed both verifications. Plus tier includes detailed metadata.

Request:
 Bash
 curl -X GET 'https://api.linkedin.com/rest/verificationReport' \
   -H 'Authorization: Bearer {ACCESS_TOKEN}' \
   -H 'LinkedIn-Version: 202510'


Response (Plus Tier with Detailed Metadata):


 JSON
 {
     "id": "zy5ubopzH4",
     "userId": "UfBk1351j0zQTGeF9TT3JCeztYB8CTz6INgveqjzg8g=",
     "lastRefreshedAt": 1761504023786,
     "verifications": ["IDENTITY", "WORKPLACE"],
     "verifiedDetails": [
       {
         "category": "IDENTITY",
         "verifiedName": {
           "firstName": "MICHAEL",
           "middleName": "GARY",
           "lastName": "SCOTT"
         },
         "lastVerifiedAt": 1744141828585
       },
       {
         "category": "WORKPLACE",
         "verificationMethod": "EMAIL_ADDRESS",
         "organizationInfo": {
           "name": "LinkedIn",
           "url": "https://www.linkedin.com/company/1337"
         },
         "lastVerifiedAt": 1744139009883
       }
     ]
 }




Example 4: Plus Tier - Partially Verified Member
Member has identity verification, eligible for workplace. URL provided for workplace
verification.

Request:


 Bash
 curl -X GET 'https://api.linkedin.com/rest/verificationReport?
 verificationCriteria=WORKPLACE' \
     -H 'Authorization: Bearer {ACCESS_TOKEN}' \
     -H 'LinkedIn-Version: 202510'


Response (Plus Tier):


 JSON

 {
   "id": "zy5ubopzH4",
   "userId": "UfBk1351j0zQTGeF9TT3JCeztYB8CTz6INgveqjzg8g=",
   "lastRefreshedAt": 1761504023786,
   "verifications": ["IDENTITY"],
   "verifiedDetails": [
     {
       "category": "IDENTITY",
       "verifiedName": {
         "firstName": "MICHAEL",
         "middleName": "GARY",
         "lastName": "SCOTT"
       },
       "lastVerifiedAt": 1744141828585
     }
   ],
   "verificationUrl": "https://www.linkedin.com/trust/verification?
 isDeeplinkToCCT=true&verificationUrl=...WORKPLACE..."
 }




Understanding Verification States
                                                                                    ﾉ   Expand table


 State            verifications     verificationUrl   Action Required

 Fully Verified   Contains all      Not present       Display verification badges
                  categories

 Partially        Contains some     Present           Show completed badges + "Complete
 Verified         categories                          Verification" button

 Not Verified     Empty array []    Present           Show "Verify with LinkedIn" button

 Not Eligible     Empty array []    Not present       Member cannot verify (region/eligibility
                                                      restrictions)




Verification URL Usage
What is verificationUrl?
The verificationUrl field is a LinkedIn URL that directs members to complete verification on
LinkedIn.

When it's present:

        Member is eligible for additional verifications
        If verificationCriteria specified: eligible for those specific verifications
        If no criteria: eligible for any verification type

When it's absent:

        Member has completed all requested verifications, OR
        Member is not eligible for any additional verifications


  ７ Note

  Member eligibility depends on factors like region, account status, and verification
  availability. See LinkedIn Help Center         for eligibility details.



Using Redirect URI (Optional)
A redirect URI (callback URL) allows LinkedIn to return the member to your application after
verification.

Flow:

   1. Your app redirects member to the verification URL
   2. Member completes verification on LinkedIn
   3. LinkedIn redirects member back to your redirect URI
   4. Your app resumes the member's session

Configuration Requirements:


  ） Important

  The redirectUri must exactly match a URL registered in your LinkedIn Developer App's
  Auth tab.


Registration Steps:

   1. Go to LinkedIn Developer Portal
  2. Select your application → Auth tab
  3. Under Authorized redirect URLs, add your redirect URI
  4. Save changes

Implementation:


 JavaScript
 // Get verification URL from API response
 const verificationUrl = apiResponse.verificationUrl;

 // Add your redirect URI (must be URL-encoded)
 const redirectUri = encodeURIComponent('https://yourapp.com/verification/callback');
 const fullUrl = `${verificationUrl}&redirectUri=${redirectUri}`;

 // Optionally add state parameter for CSRF protection
 const state = generateRandomState(); // Store this in your database
 const finalUrl = `${fullUrl}&state=${state}`;

 // Redirect member to LinkedIn
 window.location.href = finalUrl;


Handling Member's Return:


 JavaScript
 // In your callback handler at /verification/callback
 app.get('/verification/callback', async (req, res) => {
   const { state, error } = req.query;

   // Validate state parameter
   if (state && !validateState(state)) {
     return res.status(400).send('Invalid state');
   }

   // Check for errors
   if (error) {
     return res.redirect('/dashboard?message=verification_cancelled');
   }

   // Fetch updated verification data
   const verificationData = await callVerificationReportAPI(accessToken);

   // Update your database
   await updateMemberVerification(memberId, verificationData);

   // Redirect to success page
   res.redirect('/dashboard?message=verification_complete');
 });
  ２ Warning

         Do NOT cache or persist verificationUrl . Always get a fresh URL from the API.
         URLs are single-use and may expire.
         If redirectUri is omitted, member stays on LinkedIn after verification.


Common Issues:


                                                                                    ﾉ   Expand table


 Issue                       Cause                            Resolution

 Member not redirected       redirectUri not URL-encoded      URL-encode the parameter

 Redirect fails              Mismatch with registered URL     Use exact URL from Developer Portal

 Member stays on LinkedIn    Missing redirectUri parameter    Add parameter if redirect desired




Important Concepts

Verified Name vs LinkedIn Profile Name (Plus Tier)
      The verifiedName in identity verification is the legal name from government ID
      LinkedIn Profile Name comes from /identityMe API (e.g., "John Doe")
      Verified Name comes from /verificationReport API (e.g., "JOHN M DOE")
      These names may differ intentionally


Data Freshness
All Tiers:

      Check verification status before critical actions (payments, access grants)
      Consider caching responses temporarily to reduce API calls

Plus Tier:

      Use lastRefreshedAt timestamp to determine when to refresh
      Recommended refresh frequency: once per day for most use cases
      Use /validationStatus API for bulk data freshness checks
      See Data Freshness Guide for comprehensive strategies
Error Handling

Common API Errors

                                                                                          ﾉ   Expand table


 HTTP      Error                   Cause                              Solution
 Status

 400       Bad Request             Invalid verificationCriteria or    Use only IDENTITY or WORKPLACE ;
                                   comma-separated values             repeat parameter for multiple
                                                                      values

 400       API version not         Missing or invalid LinkedIn-       Include LinkedIn-Version:
           available               Version header                     {LATEST_VERSION} header


 401       Unauthorized            Invalid or expired access token    Refresh the access token and
                                                                      retry

 403       Forbidden               Missing required OAuth scope       Ensure r_verify_details scope is
                                                                      authorized

 403       Insufficient            Development tier: Non-admin        Use admin member token or
           permissions (admin      member                             upgrade to Lite tier
           required)

 403       No valid API product    Product not enabled in             Add "Verified on LinkedIn"
           assigned                Developer Portal                   product to your app

 404       Not Found               Invalid endpoint or member not     Verify request URL and member
                                   found                              status

 426       Upgrade Required        Deprecated API version             Update LinkedIn-Version header
                                                                      to latest version

 429       Too Many Requests       Rate limit exceeded                Retry after delay specified in
                                                                      Retry-After header


 500       Internal Server Error   Temporary LinkedIn service issue   Retry with exponential backoff;
                                                                      contact support if persists


For additional error handling guidance, see the LinkedIn API Error Handling Guide.




Best Practices
For All Tiers
✅ Always use LinkedIn-Version header for API compatibility
✅ Handle all verification states (fully verified, partially verified, not verified, not eligible)
✅ Use verificationUrl only for redirection – Don't expose or store it
✅ URL-encode your redirectUri before appending
✅ Validate id field uniqueness in your system
✅ Combine with /identityMe for complete member context
✅ Cache responses temporarily to reduce API calls


For Development Tier
⚠️Remember: Only admin accounts can be accessed
💡 Test verification flows thoroughly before requesting Lite tier
💡 Verify badge display in your UI


For Plus Tier
✅ Use id field (not deprecated userId )
✅ Display verified names when showing identity verification
✅ Show organization info for workplace verifications
✅ Implement data freshness checks using lastVerifiedAt timestamps
✅ Use /validationStatus API for bulk freshness validation



Use Cases

All Tiers
     Display "Verified on LinkedIn" badges
     Confirm member trust and authenticity
     Trigger verification flows for unverified members
     Build trust scores based on verification status


Plus Tier Additional Use Cases
     Display verified legal name for identity confirmation
     Show verified company affiliation with logo
     Build detailed audit trails with verification timestamps
     Implement data freshness validation workflows
     Display verification methods for transparency




Related Resources

APIs
     Profile Details API – Get member profile information
     Validation Status API – Bulk validation checks (Plus tier only)


Guides
     Quickstart Guide – Get started with the API
     Upgrade to Lite Tier – Move to production
     Implementation Guide – Best practices
     Data Freshness Strategies – Keep data current (Plus tier)
     Certification Requirements – Production readiness (Plus tier)


Authentication
     Authorization Code Flow – OAuth 2.0 3-legged authentication


Other Resources
     Branding & UX Guidelines – Display verification badges correctly
     FAQ – Troubleshooting and answers
     Release Notes – API updates and current versions
     Overview – Product overview and tier comparison



Last updated on 11/26/2025
Validation Status API (/validationStatus)
The Validation Status API ( /validationStatus ) allows enterprise partners to retrieve the current
validation status of LinkedIn members at scale. This API is optimized for bulk or single-member
checks and provides validation results across three categories.


  ） Important

  Plus Tier Only: This API is exclusively available to Plus tier partners.

  Tier Availability: Development ❌ | Lite ❌ | Plus ✅




Overview
Key Features:

     Check validation status for up to 500 members per request
     No member consent required (2-legged OAuth)
     Get identity, workplace, and profile information status
     OAuth: 2-legged (application-level authorization)
     Version: 202510


Validation Categories

                                                                                       ﾉ   Expand table


 Category                   Description                            Possible Values

 identity                   Government ID verification status      VALID , INVALID , VALID_WITH_UPDATES


 workplace                  Work affiliation verification status   VALID , INVALID , VALID_WITH_UPDATES


 profileInformationStatus   Profile data validation status         VALID , INVALID




  ） Important

  This API uses 2-legged OAuth and does NOT require member interaction or consent. You
  can call this endpoint directly to validate existing member data at scale.
Key Differences from Other APIs
                                                                                      ﾉ   Expand table


 Feature            /validationStatus        /verificationReport               /identityMe


 OAuth Type         2-legged (application)   3-legged (member)                 3-legged (member)

 Member Consent     ❌ Not required           ✅ Required                        ✅ Required

 Use Case           Bulk validation checks   Individual verification details   Individual profile details

 Batch Support      ✅ Up to 500 members      ❌ Single member                   ❌ Single member

 Returns            Validation status        Detailed verification metadata    Profile information

 Token Lifetime     30 minutes               60 days                           60 days



   Tip

  Use Case: Use this API to check if any of your members' profile or verification information
  has changed. This allows you to efficiently identify which members need data refreshes,
  then pull only the changed member data using /verificationReport and /identityMe .

  See the Data Freshness Guide for complete implementation patterns.




Prerequisites
Before using this API, ensure you're using the latest versions of related APIs to get the required
id field:


      /identityMe – Version 202510.03 or later

      /verificationReport – Version 202510 or later



  ２ Warning

  The id field returned by these endpoints is required for validation checks. Without
  upgrading to these versions, you cannot use the Validation Status API.
Authentication: 2-Legged OAuth
This API requires an application-level access token obtained through OAuth 2.0 Client
Credentials flow.


Key Characteristics
      No member consent required – Application acts on its own behalf
      Scope: r_validation_status
      Token validity: 30 minutes
      No refresh token issued – Request new token after expiry


Get Access Token

 Bash

 curl -X POST 'https://www.linkedin.com/oauth/v2/accessToken' \
   -H 'Content-Type: application/x-www-form-urlencoded' \
   --data-urlencode 'grant_type=client_credentials' \
   --data-urlencode 'client_id={YOUR_CLIENT_ID}' \
   --data-urlencode 'client_secret={YOUR_CLIENT_SECRET}' \
   --data-urlencode 'scope=r_validation_status'


Sample Response:


 JSON
 {
     "access_token": "AQVjYwl_Z-PJW2bChvx9ewKy3hrkQtJuM70LOj17...",
     "expires_in": 1799
 }



   Tip

  Request a new access token every 25 minutes to avoid expiry during API calls. Implement
  token caching and refresh logic in your application.


For complete OAuth details, see the Client Credentials Flow Guide.




Rate Limits
                                                                                ﾉ   Expand table


Limit Type          Default                 Description

Application-level   5,000 requests/day      Maximum API calls per day

Member-level        500 requests/day        Maximum checks per individual member per day



 ７ Note

 Rate limits may be customized based on your partnership agreement. Contact your
 LinkedIn Partner Solutions Engineer for details.




Endpoint Details
HTTP
POST https://api.linkedin.com/rest/validationStatus?action=retrieve




Required Headers

                                                                                ﾉ   Expand table


Header                   Value                            Description

Authorization            Bearer {ACCESS_TOKEN}            2-legged OAuth access token

LinkedIn-Version         202510                           API version

Content-Type             application/json                 Request body format



Request Body

JSON
{
    "validationQueries": [
      {
        "id": "string"
      }
    ]
}
                                                                                       ﾉ   Expand table


 Field                    Type     Required   Description

 validationQueries        array    Yes        Array of validation requests (max 500)

 validationQueries[].id   string   Yes        Member identifier from /identityMe or
                                              /verificationReport




  ） Important

         Maximum 500 queries per request
         Use the id field from /identityMe or /verificationReport responses
         Each unique member ID counts toward member-level rate limits




Example Request and Response

Single Member Validation
Request:


 Bash
 curl -X POST 'https://api.linkedin.com/rest/validationStatus?action=retrieve' \
   -H 'Authorization: Bearer {ACCESS_TOKEN}' \
   -H 'LinkedIn-Version: 202510' \
   -H 'Content-Type: application/json' \
   -d '{
     "validationQueries": [
       {"id": "abc123"}
     ]
   }'


Response:


 JSON

 {
     "value": [
       {
         "id": "abc123",
         "verificationStatus": {
           "identity": "VALID",
           "workplace": "VALID"
             },
             "profileInformationStatus": "VALID"
         }
     ]
 }




Bulk Member Validation
Request:


 Bash
 curl -X POST 'https://api.linkedin.com/rest/validationStatus?action=retrieve' \
   -H 'Authorization: Bearer {ACCESS_TOKEN}' \
   -H 'LinkedIn-Version: 202510' \
   -H 'Content-Type: application/json' \
   -d '{
     "validationQueries": [
       {"id": "abc123"},
       {"id": "def456"},
       {"id": "ghi789"}
     ]
   }'


Response:


 JSON

 {
     "value": [
       {
         "id": "abc123",
         "verificationStatus": {
           "identity": "VALID",
           "workplace": "VALID_WITH_UPDATES"
         },
         "profileInformationStatus": "VALID"
       },
       {
         "id": "def456",
         "verificationStatus": {
           "identity": "INVALID",
           "workplace": "VALID"
         },
         "profileInformationStatus": "INVALID"
       },
       {
         "id": "ghi789",
         "verificationStatus": {
           "identity": "VALID",
                "workplace": "VALID"
              },
              "profileInformationStatus": "VALID"
          }
      ]
}




Response Schema

Top-Level Fields

                                                                                                 ﾉ    Expand table


Field             Type                         Description

 value            array of objects             List of validation results (one per member)



Validation Result Object

                                                                                                 ﾉ    Expand table


Field                                   Type        Description

 id                                     string      Member identifier (same as submitted in request)

 verificationStatus                     object      Identity and workplace verification status

 profileInformationStatus               string      Profile data validation status



verificationStatus Object

                                                                                                 ﾉ    Expand table


Field               Type      Description

 identity           string    Identity verification status: VALID , INVALID , or VALID_WITH_UPDATES

 workplace          string    Workplace verification status: VALID , INVALID , or VALID_WITH_UPDATES



Status Values Explained
                                                                                     ﾉ   Expand table


 Value                Applies To   Description                         Action Required

 VALID                All fields   Information is current and valid    No action needed

 INVALID              All fields   Information is no longer valid      Fetch fresh data via
                                   (verification removed or expired)   /verificationReport and
                                                                       /identityMe


 VALID_WITH_UPDATES   identity,    Information is valid, but updates   Fetch updated data if you need
                      workplace    are available (new verifications    the latest verification details
                                   added or existing re-verified)



Decision Logic

 JavaScript
 // Example: Determine which members need data refresh
 results.value.forEach(member => {
   const { id, verificationStatus, profileInformationStatus } = member;

   // Check if any verification changed
   if (verificationStatus.identity === 'INVALID' ||
       verificationStatus.identity === 'VALID_WITH_UPDATES' ||
       verificationStatus.workplace === 'INVALID' ||
       verificationStatus.workplace === 'VALID_WITH_UPDATES') {
     // Fetch fresh verification data
     refreshVerificationData(id);
   }

   // Check if profile changed
   if (profileInformationStatus === 'INVALID') {
     // Fetch fresh profile data
     refreshProfileData(id);
   }
 });




Best Practices

Token Management
✅ Cache tokens - Don't request new tokens for every API call
✅ Refresh proactively - Get new token at 25 minutes (before 30-minute expiry)
✅ Handle 401 errors gracefully - Automatically retry with fresh token
Batching Strategy
✅ Batch up to 500 members - Maximize efficiency by filling each request
✅ Parallel requests - Send multiple batches in parallel for large datasets
✅ Respect rate limits - Track daily and per-member limits


Data Freshness Workflow
   1. Daily validation - Run bulk validation once per day for all members
   2. Identify changes - Filter members with INVALID or VALID_WITH_UPDATES status
   3. Fetch fresh data - Call /verificationReport and /identityMe only for changed members
   4. Update database - Store latest verification and profile data


   Tip

  This approach reduces 3-legged OAuth API calls by 95% compared to polling all members
  daily.



Error Handling
✅ Validate id format before sending requests
✅ Handle partial failures gracefully (some IDs may be invalid)
✅ Implement exponential backoff for 500 errors
✅ Log failed IDs for investigation



Error Handling

API-Specific Errors

                                                                                 ﾉ   Expand table


 HTTP      Error Code                 Error Message    Cause                 Solution
 Status

 400       S_400_BAD_REQUEST          "Validation      Empty                 Include at least one
                                      status request   validationQueries     validation query
                                      array cannot     array
                                      be null or
                                      empty"
 HTTP     Error Code                    Error Message      Cause                   Solution
 Status

 400      S_400_BAD_REQUEST             "Validation        Request exceeds 500     Split into multiple
                                        status request     items                   requests with max
                                        array size                                 500 queries each
                                        ({size}) exceeds
                                        maximum limit
                                        of 500"

 400      S_400_BAD_REQUEST             "Invalid           Invalid or malformed    Use valid id from
                                        personId:          member ID               /identityMe or
                                        {personId}"                                /verificationReport


 400      S_400_BAD_REQUEST             "API version is    Missing or invalid      Include LinkedIn-
                                        not available in   LinkedIn-Version        Version: 202510
                                        the request"       header                  header

 401      -                             Unauthorized       Invalid or expired 2-   Request new token
                                                           legged token            using client
                                                                                   credentials flow

 403      -                             Access denied      r_validation_status     Contact LinkedIn
                                                           permission not          Partner Solutions
                                                           enabled                 Engineer

 429      -                             Too Many           Rate limit exceeded     Retry after delay;
                                        Requests                                   check Retry-After
                                                                                   header

 500      S_500_INTERNAL_SERVER_ERROR   "Failed to get     Downstream service      Retry with
                                        validation         failure                 exponential backoff;
                                        status                                     contact support if
                                        response"                                  persists


For additional error handling guidance, see the LinkedIn API Error Handling Guide.


  ７ Note

  If you receive a 403 "access denied" error, contact your LinkedIn Partner Solutions
  Engineer to enable the r_validation_status permission for your application.




Common Use Cases
1. Daily Data Freshness Check
Validate all members once per day to identify who needs data refresh:


 JavaScript
 // Step 1: Get all member IDs from your database
 const allMemberIds = await db.getAllMemberIds();

 // Step 2: Batch into groups of 500
 const batches = chunk(allMemberIds, 500);

 // Step 3: Validate each batch
 const validationResults = await Promise.all(
    batches.map(batch => validateMembers(batch))
 );

 // Step 4: Identify members needing refresh
 const membersToRefresh = validationResults
   .flat()
   .filter(m =>
     m.verificationStatus.identity !== 'VALID' ||
     m.verificationStatus.workplace !== 'VALID' ||
     m.profileInformationStatus === 'INVALID'
   );

 // Step 5: Refresh only changed members
 await refreshMemberData(membersToRefresh);




2. Pre-Transaction Validation
Validate member data before critical transactions:


 JavaScript
 // Before processing payment or granting access
 const validation = await validateMember(memberId);

 if (validation.verificationStatus.identity === 'INVALID') {
   // Identity no longer valid - require re-verification
   return redirectToReVerification(memberId);
 }

 if (validation.verificationStatus.workplace === 'INVALID') {
   // Workplace verification removed - update member status
   await updateMemberWorkplaceStatus(memberId, 'unverified');
 }

 // Proceed with transaction
3. Compliance Audit Trail
Track verification status changes over time:


 JavaScript
 // Daily compliance check
 const results = await bulkValidateMembers(allMemberIds);

 // Store validation results with timestamp
 await db.saveValidationSnapshot({
   timestamp: Date.now(),
   results: results,
   summary: {
     totalMembers: results.length,
     validMembers: results.filter(r => r.verificationStatus.identity ===
 'VALID').length,
     invalidMembers: results.filter(r => r.verificationStatus.identity ===
 'INVALID').length,
     updatedMembers: results.filter(r => r.verificationStatus.identity ===
 'VALID_WITH_UPDATES').length
   }
 });




Related Resources

APIs
     Profile Details API – Get member profile information
     Verification Report API – Get detailed verification metadata


Guides
     Client Credentials Flow – OAuth 2.0 2-legged authentication
     Data Freshness Strategies – Keep member data up-to-date with polling strategies
     Implementation Guide – Best practices for OAuth, user ID management, and token
     storage


Other Resources
     Overview – Learn about Plus tier features
     Certification Requirements – Production readiness checklist
     Common FAQ – Troubleshooting and answers
     LinkedIn API Status Page   – Monitor API health
     Release Notes – API updates and current versions



Last updated on 11/26/2025
Verified on LinkedIn – Branding & UX
Guidelines
Partners integrating the Verified on LinkedIn API must follow these branding and UX
guidelines to ensure a consistent and trusted member experience.

This page explains the correct usage of the “Verify on LinkedIn” button, the “Verified on
LinkedIn” badge, and the associated placement and design standards.


  ７ Note

  Visual assets (buttons, badges, and icons) must only be used as provided by LinkedIn.
  Partners may not alter these assets or create custom “verified” visuals that could mislead
  Members about verification sources or statuses.




Overview
The Verified on LinkedIn visual system represents trust and authenticity for LinkedIn members
across partner experiences.
Proper implementation ensures the integrity of LinkedIn’s verification experience and
reinforces credibility and security for end users.

Key Principles

     Always use the official button and badge assets provided by LinkedIn.
     Maintain sizing, color, and spacing to ensure visual consistency.
     Do not modify or recreate any verification icons, logos, or phrases.
     Do not misstate or overstate what Verified on LinkedIn means.



“Verify on LinkedIn” Button
The “Verify on LinkedIn” button is the primary call-to-action (CTA) for users to start the
verification flow on LinkedIn.
It must link directly to the verificationUrl returned from the /verificationReport API.


Button Usage Rules

                                                                                ﾉ   Expand table
 Rule          Description

 Purpose       Routes members to LinkedIn to complete identity or workplace verification.

 Placement     Display in contexts where verification is required

 State         Render only when the API response includes a valid verificationUrl .

 Do not        Do not cache the URL — use the latest verificationUrl from each API response.
 cache

 Label         Button text must remain “Verify on LinkedIn”. No modifications such as “LinkedIn Verify”
               or “Verify via LinkedIn”.



Button Design




Sizing and color options

We want your team to utilize the best sizing of our "Verify on LinkedIn" button for your
experience. However, we want to limit use of the button being too small or too large as it
impacts the visual design aesthetic, impact, and brand perception. To ensure the main call to
action is prominent and consistent across partner sites, we ask that the blue version be used
and inverted white colors used in dark mode.




Interaction

Use "button" states to suggest interaction. This includes the enabled, hover and active state.
Application Example




"Verified on LinkedIn" Badge
The "Verified on LinkedIn" badge is a visual signal confirming that a member has completed
one or more verification types (Identity or Workplace) through LinkedIn.


When to Display

                                                                              ﾉ   Expand table


 Condition                                                             Display the Badge?

 At least one verification type (Identity or Workplace) is true.       Yes

 After verification completes (no verificationUrl returned).           Yes

 Member is unverified or verification data is missing.                 No

 Data is from cached or manually entered sources.                      No



Badge Design
Sizing and color options
To maintain a consistent experience, the badge should adhere to recommended sizing
guidelines. Avoid making it too small, which can reduce visibility and usability, or too large,
which can disrupt the visual hierarchy and negatively impact brand perception. Proper sizing
ensures the badge remains clear, functional, and aesthetically aligned with the overall design
system.




Interaction
The badge acts as a clickable element that navigates directly to the user's LinkedIn profile,
enabling quick access for others to view professional details. Use "button" states to suggest
interaction. This includes the enabled, hover and active state.




Application example:
Do's and Don'ts
   Do
      Use official assets from LinkedIn's API documentation.
      Maintain proportional spacing and readable font sizes.

   Don't
      Change text to "LinkedIn Verified", "LinkedIn Trusted", or any other non-approved
      language.
      Alter badge colors or replace icons.
      Show the badge before confirmation from API response.
      Combine with other third-party verification marks.



Example UX Flow
 1. Your app calls the /verificationReport endpoint to check the member's current
   verification categories.
 2. If the API response includes a verificationUrl , display the "Verify on LinkedIn" button.
 3. When the member clicks the button, they are redirected to LinkedIn to complete
   verification.
 4. After completion, LinkedIn redirects the member back to your app's registered redirect
   URL.
 5. Your app calls /verificationReport again to confirm the updated verification categories.
 6. Once verified, display the "Verified on LinkedIn" badge in the appropriate location (for
   example, profile header or account summary).



Obtaining Design Assets
Official assets for the "Verify on LinkedIn" button and "Verified on LinkedIn" badge are
available for partner use.

Download Asset Kit (.zip)

Have a design-related question? Check the Verified on LinkedIn FAQ, for usage clarifications
and implementation tips.

  Important:
  Unauthorized reproduction or modification of LinkedIn marks is strictly prohibited.
  All implementations must comply with LinkedIn Brand Guidelines and Partner Terms.



Next Steps
      Review the Verified on LinkedIn API to understand key API capabilities.
      Explore API Reference for implementation details.
      Stay up to date with Release Notes for new asset or schema updates.



 Last updated on 11/13/2025
Verified on LinkedIn - FAQ
This comprehensive FAQ provides answers to common questions about integrating and using
the Verified on LinkedIn API, including access, authentication, data returned, policy guidelines,
and developer support.




Getting Started

What is the Verified on LinkedIn API?

The Verified on LinkedIn API enables you to retrieve LinkedIn members' verified identity and
workplace information after they grant explicit consent through OAuth 2.0. You can display the
"Verified on LinkedIn" badge within your app to build trust and authenticity into your
platform.

More than 80 million LinkedIn members have confirmed their identity with a government-
issued ID or verified their workplace using a company email. Read more about LinkedIn
verifications   .


What are the different tiers?

LinkedIn offers three tiers of the Verified on LinkedIn API:


                                                                                   ﾉ   Expand table


 Tier               Best For              Access                            Cost        Rate
                                                                                        Limits

 Development        Testing &             Developer app admins only         Free        5,000/day
                    prototyping

 Lite               SMBs & startups       All LinkedIn members              Free        5,000/day

 Plus               Enterprise partners   All LinkedIn members + enhanced   Contact     Custom
                                          data                              us


See Overview for detailed tier comparison.


How do I choose which tier to use?

        Development: Start here to test the API with your admin account. Perfect for prototyping
        and learning.
     Lite: Ready for production with basic verification data. No cost, suitable for SMBs and
     startups.
     Plus: Enterprise-grade with detailed verification metadata, organization details, and bulk
     validation API. Requires business partnership.


What data does each tier return?

     All Tiers: Completed verification categories ( IDENTITY , WORKPLACE ), and a verificationUrl
     for members eligible to complete missing verifications.
     Plus Tier Only: Organization names, verification methods, verification timestamps,
     education data, and full profile details.


  ７ Note

  For extended metadata (organization details, verification methods, timestamps), use
  Verified on LinkedIn Plus. See Overview for tier comparison.




What Member consent is required?

Members must explicitly grant consent via LinkedIn's OAuth 2.0 authorization flow before your
app can access their verification data. Without consent, no data can be retrieved. Consent is
required once unless you add new scopes.


Does the API share unverified or pending data?

No. The API only returns completed verification categories. Members who are not yet verified
will receive a verificationUrl to complete the process on LinkedIn.



Can Members revoke access?
Yes. Members can revoke access anytime from their LinkedIn account settings at
https://www.linkedin.com/mypreferences/d/data-sharing-for-permitted-services        . After
revocation, all subsequent API requests return 401 Unauthorized until the member re-consents.




OAuth & Authentication

Which OAuth scopes are required?
Development & Lite Tiers:

      r_profile_basicinfo – Basic profile information (name, email, profile URL, picture)

      r_verify – Verification categories only


Plus Tier:

      r_verify_details – Detailed verification status and metadata

      r_profile_basicinfo – Basic profile information
      r_most_recent_education – Most recent education details

      r_primary_current_experience – Current workplace information



  ） Important

  Key Difference: r_verify returns only verification categories (e.g., ["IDENTITY",
  "WORKPLACE"] ), while r_verify_details returns full metadata including verified names,

  timestamps, methods, and organization details.




How do I obtain access tokens?

Use the OAuth 2.0 Authorization Code flow to exchange an authorization code for an access
token and refresh token.

Token Characteristics:

     Access tokens are valid for 60 days
     Refresh tokens remain valid for 1 year and can be used to obtain new access tokens
     without requiring member re-consent
     Member consent is required once (unless you add new scopes)

For detailed implementation, see Authorization Code Flow Guide.


Should I request all scopes at once?

Yes. Request all required scopes in a single authorization request to provide the best user
experience and avoid multiple authorization prompts. This gives you:

     ✅ Single consent flow - Member authorizes once instead of multiple times
     ✅ Complete data access - Get all profile and verification data in one session
     ✅ Better UX - Avoid interrupting member with additional authorization requests
     ✅ Simplified implementation - No need to manage partial authorization states
What happens when my access token expires?
When an access token expires, API calls return 401 Unauthorized . Use your refresh token to
obtain a new access token without requiring the member to re-authorize. If the refresh token
has also expired (after 1 year), the member must complete the OAuth flow again.

See Authentication Guide for implementation details.



Do tokens work across tier upgrades?
Yes! When you upgrade from Development to Lite or Lite to Plus:

       Existing access tokens remain valid
       Members don't need to re-authorize (unless you add new scopes)
       Only request new consent if adding scopes



How do I add more scopes?
If you need additional OAuth scopes (e.g., upgrading to Plus tier):

   1. Update your authorization URL with new scopes
   2. Ask member to re-authorize
   3. New tokens will include additional scopes




API Integration

What endpoints should I use?

                                                                                     ﾉ   Expand table


 API                   Purpose           Development     Lite            Plus

 /identityMe           Profile data      Basic profile   Basic profile   Full profile + job +
                                                                         education

 /verificationReport   Verification      Categories      Categories      Categories + Verification
                       status            only            only            details

 /validationStatus     Bulk validation   ❌               ❌               ✅ Validation statuses

See Release Notes for the current version of each API endpoint.
What is the correct API request format?

 HTTP
 GET https://api.linkedin.com/rest/verificationReport


Use headers:


 HTTP
 LinkedIn-Version: {LATEST_VERSION}
 Authorization: Bearer {ACCESS_TOKEN}




What should I do if the API returns a verificationUrl ?

Display a "Verify on LinkedIn" button and redirect the member to the returned URL. After the
member completes verification on LinkedIn, call /verificationReport again to refresh the
updated verification categories.

Always re-query /verificationReport to obtain a fresh verificationUrl instead of reusing
older links, as they may expire.



Can I store verification results?
You may cache verification results temporarily for performance optimization, but you must:

     Refresh them periodically to ensure accuracy
     Comply with LinkedIn's API Terms
     Not store verification data indefinitely

For Plus tier, see Data Freshness Guide for best practices on keeping member data up-to-date.



Can I show badges for all users?
Only display the "Verified on LinkedIn" badge for users who have completed one or more
verification categories, as indicated by the API response. Follow the Branding & UX Guidelines
for correct badge usage.


What are the rate limits?

                                                                              ﾉ   Expand table
 Type                                     Limit

 Per Application                          5,000 requests per day

 Per member                               500 requests per day


If you exceed these limits, the API returns a 429 Too Many Requests response.


What timeout should I use?
     Standard endpoints ( /identityMe , /verificationReport ): 5 seconds
     Bulk validation ( /validationStatus ): 30 seconds



How do I handle missing optional fields?

Some fields may be missing from API responses (e.g., email address, profile picture). Your
implementation should:

     ✅ Handle missing optional fields gracefully
     ✅ Display fallback content when data is unavailable
     ✅ Log missing fields for debugging


How do I validate member ID uniqueness?
This is critical for security. You must validate that each id is unique in your system to prevent
a single LinkedIn account from verifying multiple accounts on your platform.

Best Practices:

     ✅ Enforce uniqueness at the database level (UNIQUE constraint)
     ✅ Check for existing LinkedIn ID before saving new verification
     ✅ Log security alerts when duplicate attempts are detected
     ✅ Display clear error messages to members
     ✅ Provide support contact for legitimate edge cases

  ７ Note

  Always use the id field (available since version 202510). The userId field will be
  deprecated in future versions and should only be used for temporary backward
  compatibility during migration from older API versions.
Data Freshness & Push Notifications

How do I keep member data up-to-date?
Plus tier only. You have two options:

   1. Polling with /validationStatus – Call the bulk validation API daily to check if member
     data has changed
   2. Push Notifications – Receive real-time webhooks when member data changes

See Data Freshness Guide for detailed implementation strategies.



What is the /validationStatus API?
The /validationStatus API (Plus tier only) allows you to bulk-check up to 500 members at
once to see if their verification or profile data has changed. It returns status values:

      VALID – Data is current, no action needed

      INVALID – Data should be refreshed by calling /verificationReport and /identityMe
      VALID_WITH_UPDATES – Data is valid but member re-verified (optional refresh)


This reduces unnecessary API calls compared to polling individual members.


How do push notifications work?

Push notifications provide real-time updates when member data changes. To use them:

   1. Contact LinkedIn API Support to set up webhooks for your application
   2. Receive FEDERATED_MEMBER_DATA_STATUS_CHANGE events when member data changes
   3. Refresh data by calling /verificationReport and /identityMe with the member's access
     token


  ） Important

  Push notifications indicate that changes exist—they do not contain the actual updated
  data. You must call the actual endpoints to retrieve the new data.



What should I do when I receive a push notification?

   1. Check if isAccessRevoked is true :
           If yes → Remove the member's data from your system
           If no → Continue to step 2
   2. Check the status fields in the notification:

           INVALID → Must refresh data by calling /verificationReport and/or /identityMe

           VALID_WITH_UPDATES → Optionally refresh to get latest data

           VALID → No action needed


   3. Call the appropriate endpoints with the member's access token
   4. Update your stored data



What fields should I persist for data freshness?
To implement data freshness strategies, you must store:


                                                                                       ﾉ   Expand table


 Field                Why It's Critical

 id                   Required for /validationStatus checks and push notifications

 refresh_token        Needed to obtain new access tokens without member re-authorization

 lastRefreshedAt      Timestamp to ignore stale notifications and avoid unnecessary API calls




How do I implement polling with /validationStatus ?
Polling involves two steps:

Step 1: Check Status (2-legged OAuth, no member consent needed)

      Call /validationStatus with up to 500 member id s in a single request
      Receive status for each member: VALID , INVALID , or VALID_WITH_UPDATES

Step 2: Refresh Data (3-legged OAuth, member consent required)

      For members with INVALID or VALID_WITH_UPDATES status only
      Call /verificationReport and /identityMe with the member's access token
      Store the updated data

This two-step approach minimizes API calls by only refreshing data for members who have
changes.
How often should I poll for data changes?
Recommended: Once per day during off-peak hours.

Best Practices:

     ✅ Run polling during off-peak hours to minimize impact
     ✅ Batch requests (up to 500 members per call) to stay within rate limits
     ✅ Only call actual endpoints for members with VALID_WITH_UPDATES or INVALID status
     ✅ Implement exponential backoff for rate limit errors
     ✅ Store critical fields ( id , refresh_token , lastRefreshedAt ) before implementing polling


Is data freshness available for all tiers?
No. Data freshness strategies (polling and push notifications) are Plus tier only. Development
and Lite tiers do not have access to /validationStatus or push notifications.




Security & Data Handling

How should I store OAuth tokens?
This is critical for security. You must securely store OAuth access tokens and refresh tokens
with encryption.

Best Practices:

     ✅ Encrypt tokens using AES-256-GCM or equivalent
     ✅ Store in secure backend database with proper access controls
     ✅ Implement token rotation and secure deletion policies
     ✅ Never store tokens in client-side storage (cookies, localStorage, sessionStorage)
     ✅ Log access to tokens for audit purposes


Why do I need to store refresh tokens?

Storing refresh tokens is necessary to generate new access tokens when needed to refresh
member data without requiring the member to re-authorize. This enables you to keep member
profile and verification information up-to-date through background processes.


What are the general security best practices?
     ✅ Store tokens securely – Encrypt at rest, never expose in client-side code
     ✅ Use refresh tokens – Don't make users re-authenticate every 60 days
     ✅ Request minimum scopes – Only request what you need
     ✅ Handle token expiry gracefully – Implement automatic refresh logic
     ✅ Validate redirect URIs – Must match exactly with Developer Portal settings
     ✅ Implement CSRF protection – Use state parameter in OAuth flow
     ✅ Use HTTPS only for all API calls



Policy & Compliance

What are the approved use cases?
The API is designed for trust enhancement, not regulatory compliance or eligibility decisions.
Approved use cases include:


                                                                                           ﾉ    Expand table


 Category                  Examples

 Trust & Safety            Professional communities, networking platforms, online marketplaces, peer-to-
                           peer exchanges

 Communities &             Event registration, professional conferences, community moderation, alumni
 Networks                  groups

 Marketplaces              Buyer/seller verification, freelance platforms, service-sharing, resale platforms




What are the restricted use cases?
The API cannot be used for:


                                                                                           ﾉ    Expand table


 Restricted Use Case                    Reason

 Hiring or employment decisions         Not an employment screening tool. Do not use to rank or approve
                                        candidates.

 Background checks                      Does not include criminal, financial, or government background
                                        data.

 Credit, loans, or insurance            Not related to creditworthiness or insurability.
 Restricted Use Case                    Reason

 Housing eligibility                    Cannot be used for rental or housing determinations.

 Fintech or banking KYC                 Not a regulated KYC/AML service.

 Government or regulated identity       Not a substitute for official ID verification systems.
 checks

 Platform safety or risk scoring        Should complement — not replace your platform's trust and risk
                                        systems.




Can I use this API for background checks or credit decisions?
No. The API cannot be used for employment eligibility, credit scoring, housing, or any similar
decision-making purposes.



Can I aggregate or resell LinkedIn verification data?
No. You may only use verification data within your own app for the member who granted
consent. Aggregation, resale, or redistribution is strictly prohibited.


Is there a review process?

Yes. Verified on LinkedIn applications undergo automated and manual reviews. LinkedIn may
request clarifications or revoke access for policy violations.




Branding & UX

How should I display the "Verify on LinkedIn" button?
     Purpose: Routes members to LinkedIn to complete identity or workplace verification
     Placement: Display in contexts where verification is required
     State: Render only when the API response includes a valid verificationUrl
     Label: Button text must remain "Verify on LinkedIn". No modifications such as "LinkedIn
     Verify" or "Verify via LinkedIn"
     Do not cache: Always use the latest verificationUrl from each API response

See Branding & UX Guidelines for design specifications and asset downloads.
When should I display the "Verified on LinkedIn" badge?
Display the badge when:

        ✅ At least one verification type (Identity or Workplace) is completed
        ✅ After verification completes (no verificationUrl returned)

Do not display the badge when:

        ❌ Member is unverified or verification data is missing
        ❌ Data is from cached or manually entered sources


What design assets are available?

Official assets for the "Verify on LinkedIn" button and "Verified on LinkedIn" badge are
available for partner use. Download Asset Kit (.zip)



What are the branding rules?
Do's:

        ✅ Use official assets from LinkedIn's API documentation
        ✅ Maintain proportional spacing and readable font sizes

Don'ts:

        ❌ Change text to "LinkedIn Verified", "LinkedIn Trusted", or any other non-approved
        language
        ❌ Alter badge colors or replace icons
        ❌ Show the badge before confirmation from API response
        ❌ Combine with other third-party verification marks



Troubleshooting

Where can I get technical help?

For technical issues or troubleshooting, please submit a support ticket     and include:

        App name and Client ID
        API endpoint and version
        Timestamp and sample request/response
What do I do if I get a 401 Unauthorized error?

This typically means:

     Your access token has expired – Use your refresh token to get a new one
     Your refresh token has expired – Ask the member to re-authorize
     The member revoked access – Ask them to re-authorize from your app


What do I do if I get a 403 Forbidden error?
Ensure your access token includes the required scopes:

     Development/Lite: r_verify and r_profile_basicinfo
     Plus: r_verify_details , r_profile_basicinfo , r_most_recent_education ,
      r_primary_current_experience



What do I do if I get a 429 Too Many Requests error?
You've exceeded rate limits. Check:

     Per Application: 5,000 requests per day
     Per member: 500 requests per day

Implement request throttling and caching to reduce API calls.


My redirect URI isn't working. What should I check?
Ensure your redirect URI exactly matches the one configured in your app settings in the
Developer Portal. The match is case-sensitive and must include the protocol (http/https).


The verificationUrl returned is expired or invalid. What should I do?

Always re-query /verificationReport to obtain a fresh verificationUrl instead of reusing
older links. URLs expire after a period of time.


How long does verification remain valid?
Verification categories reflect LinkedIn's current record for the member. If the member updates
or removes their verification, the API response will reflect the change accordingly. This is why
you should refresh verification data periodically.
How do I test my integration?
Follow these test scenarios:

     ✅ Test successful OAuth authorization
     ✅ Test member denies authorization (handle gracefully)
     ✅ Test token expiry and refresh
     ✅ Call /identityMe with valid token
     ✅ Call /verificationReport with valid token
     ✅ Test with fully verified members (IDENTITY + WORKPLACE)
     ✅ Test with partially verified members (IDENTITY only or WORKPLACE only)
     ✅ Test with unverified members
     ✅ Test error handling (invalid token, insufficient scopes, rate limits)
See Implementation Guide for detailed testing strategies.




Tier-Specific Questions

How do I get started with Development tier?
Follow the Development Tier Quickstart (10 minutes). You can test with your admin account
immediately.


How do I upgrade to Lite tier?

Follow the Lite Tier Quickstart (10 minutes). Your app will undergo application review before
production access is granted.


How do I get access to Plus tier?
To request access to Verified on LinkedIn Plus, submit a partnership request    . A member of
LinkedIn's Business Development team will review and respond.

Plus tier includes:

     Enterprise-grade verification metadata
     Organization details and verification methods
     Timestamps for all verification events
     Bulk validation API ( /validationStatus )
     Custom rate limits
      Dedicated support


What is the Plus tier certification process?
Enterprise partners integrating Verified on LinkedIn Plus complete a guided certification
process with LinkedIn's Partner Solutions Engineering (PSE) team. During certification, you
validate:

      OAuth integration and token handling
      Verification workflows and redirect flows
      UI display of verification badges
      Error handling and fallback behavior

See Certification Requirements for detailed guidance.


For technical issues, where do I go?
Continue to use the Developer Support portal      for technical issues and troubleshooting.




Related Resources
      Overview - Product overview and tier comparison
      API Reference - Complete API documentation
      Implementation Guide - Integration best practices
      Branding & UX Guidelines - Button and badge usage
      Release Notes - Version history and updates



 Last updated on 11/26/2025
Verified on LinkedIn – Release Notes
The Verified on LinkedIn API enables developers and partners to display LinkedIn-trusted
verification signals—confirming a member's identity, workplace, and other professional
attributes—within their own platforms.

This page summarizes release updates, key features, and known limitations of the Verified on
LinkedIn API.




Current API Versions
Use the latest versions in the LinkedIn-Version header for all API requests:


                                                                                     ﾉ   Expand table


 API Endpoint          Current         Description
                       Version

 /identityMe           202510.03       Retrieve member profile details (name, email, education,
                                       position)

 /verificationReport   202510          Retrieve verification status and metadata

 /validationStatus     202510          Bulk validation checks (Plus tier only)



  ） Important

  Always use the latest versions listed above in all API requests.




What’s New in the Latest Release

Release Highlights – Latest Version

/identityMe — Version 202510.03 (Latest)

What changed vs. 202507.03:

     Removed basicInfo.headline
     Added basicInfo.primaryEmailAddress
     All other fields in mostRecentEducation and primaryCurrentPosition remain unchanged



/verificationReport — Version 202510 (Latest)
Added a new top-level field verifications that summarizes a member’s verified categories (for
example, ["WORKPLACE"] or ["IDENTITY"] ), in addition to the existing verifiedDetails array.

Verification Categories


                                                                                       ﾉ   Expand table


 Category      Description

 WORKPLACE     Indicates the member’s workplace has been verified (for example, through a work email
               address).

 IDENTITY      Indicates the member’s identity has been verified using a government ID or similar
               credential.




/validationStatus — Version 202510 (Latest)

No schema or behavior changes compared to 202507. The API continues to:

     Return verificationStatus.workplace
     Return verificationStatus.identity
     Return profileInformationStatus
     Use 2-legged application authorization ( r_validation_status )
     Support bulk and single-member validation checks



Version History
                                                                                       ﾉ   Expand table


 Version     Endpoint              Summary                   Details

 202510.03   /identityMe           Removed headline,         In version 202510.03, /identityMe
                                   added                     responses no longer include
                                   primaryEmailAddress       basicInfo.headline and instead include
                                                             basicInfo.primaryEmailAddress . All other
                                                             fields remain unchanged from 202507.03.

 202507.03   /identityMe           Added                     Includes everything from 202507, plus
                                    lastRefreshedAt           lastRefreshedAt .
Version     Endpoint               Summary                   Details

202507       /identityMe           Added companyPageUrl      Includes everything from 202501, plus
                                                             company page URL in
                                                             primaryCurrentPosition .


202510       /verificationReport   Added verifications       A new top-level verifications field
                                   field                     summarizes a member’s verified categories
                                                             (e.g., WORKPLACE , IDENTITY ), alongside
                                                             existing verifiedDetails .

202510       /validationStatus     No change vs 202507       Supports up to 500 queries per request.
                                                             Requires the id from /identityMe or
                                                             /verificationReport responses. The
                                                             response structure and semantics remain
                                                             identical to 202507.




Key Features
                                                                                          ﾉ   Expand table


Feature                             Description

Consistent OAuth 2.0                Used across all tiers for secure Member consent.
Authorization Code Flow

Standardized Member ID field        Consistent ID handling for member identification.

Unified verification categories     Common taxonomy across Identity and Workplace.

Simplified redirect flow            LinkedIn automatically redirects Members to the registered redirect
                                    URI after completing verifications.




Next Steps
    Review the Verified on LinkedIn Quickstart Guide and API Reference.
    Follow the Verified on LinkedIn Overview for API details.
    See the Branding & UX Guidelines for approved "Verified on LinkedIn" assets.
    Explore Certification Requirements for enterprise integrations.
    Stay up to date via the LinkedIn Engineering Blog          for product and version
    announcements.
Last updated on 01/21/2026
