# Frequently Asked Questions

Overview
All new applications created on the LinkedIn Developer Platform as of January 14, 2019
can use LinkedIn's v2 APIs. Starting May 1, 2019, LinkedIn will deprecate use of its v1
APIs    . If your developer application currently depends on LinkedIn v1 APIs, see the
frequently asked questions below before migrating to LinkedIn v2 APIs.


Does my developer application have access to the
LinkedIn v2 API?
All developer applications created on the LinkedIn Developer Portal after January 14,
2019 have access to the LinkedIn v2 API by default. Alternatively, if your developer
application has made a successful LinkedIn v1 API request from September 1, 2018 to
December 17, 2018, your developer application has immediate access to the v2 API.


What permissions do I have access to?
LinkedIn v1 APIs provided the following set of permissions:

       r_basicprofile
       r_emailaddress
       w_share
       rw_company_admin

Moving forward, the available v2 APIs include:

       r_liteprofile (replaces r_basicprofile)
       r_emailaddress
       w_member_social (replaces w_share)

Looking to maintain access to rw_company_admin? Apply to the LinkedIn Marketing API
Program      to continue managing your Company Pages.


What are the main differences with the new Sign In with
LinkedIn?
With Sign In with LinkedIn, developer applications have access to a member's Basic
Profile. In the interest of providing members with greater control over their data, Sign In
with LinkedIn using OpenID Connect returns only the critical pieces of member data
necessary for identification. The v2 API permits usage of the Lite Profile consisting of a
member's id, first name, last name, and profile picture.

A request to retrieve the member profile in v1 may resemble

  HTTP


  GET https://api.linkedin.com/v1/people/~



The equivalent request to retrieve the member profile in v2 follows:

  HTTP


  GET https://api.linkedin.com/v2/me



Looking to maintain access to the Basic Profile fields? Learn more     about LinkedIn
Developer Enterprise products.


How do I retrieve the member's email address?
There are no changes to the r_emailaddress permission scope used to retrieve the
authenticated member's email address. However, the method used to retrieve the email
address has been updated.

Whereas the v1 Profile API returned the email address within the Profile response body,
a separate request is to retrieve the email address is now required. Use the request
below to retrieve the currently authenticated member's email address:

  HTTP


  GET https://api.linkedin.com/v2/emailAddress?q=members&projection=(elements*
  (handle~))




Troubleshooting
If you have not yet adjusted your application to work around these changes, you will
begin to see critical errors occurring now, or in the near future when your authentication
tokens next expire. Here are some tips for resolving common potential issues:
   1. The most common problem that will occur as a result of the API changes is that
     your authentication workflow will fail because your app is attempting to request
     member permissions that you no longer have access to.

     To correct this issue, ensure that the scope parameter in your authorization
     workflow is no longer requesting any of the following member permissions:

      r_basicprofile , w_share , rw_company_admin .


     Additionally, default scopes are no longer permitted. For all OAuth authorization
     code requests, make sure to include the proper scope with your request. The
      scope parameter along with the requested scope must be present within your
     OAuth request.

     Pay special attention to any 3rd party libraries that you are using for authenticating
     with LinkedIn, as they may be asking for more member permissions than you
     realize!

     Note that by removing member permissions, you may also be required to remove
     API calls that depend on those permissions being present, so you will need to
     thoroughly review your application and ensure that all of the API calls that it makes
     can be done under the remaining member permissions.

   2. Over the default access token life cycle, even after your LinkedIn API access
     changes, your application may still have some users with an access token that
     allows them to call APIs that are no longer available to you.

     When your API access changes, your application may not immediately experience
     the impact of the changes until your current user access tokens start to expire and
     you are forced to refresh them to continue making API calls. Please ensure your
     application is prepared to handle access tokens that were granted before your API
     access was changed so that they do not request unavailable permissions upon
     refresh.
