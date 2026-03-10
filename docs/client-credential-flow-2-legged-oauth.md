# Client Credential Flow (2-legged OAuth)

If your application needs to access APIs that are not member specific, use the Client
Credential Flow. Your application cannot access these APIs by default.

Learn more:

      LinkedIn Developer Enterprise products      and permission requests.
      LinkedIn Developers Platform     knowledge base.


  ） Important

  2-legged OAuth authentication is not available for Marketing APIs



  ７ Note

  Generate a Token Manually Using the Developer Portal
  The LinkedIn Developer Portal has a token generator for manually creating tokens.
  Visit the LinkedIn Developer Portal Token Generator        or follow the steps outlined
  in Developer Portal Tools.




Step 1: Get Client ID and Client Secret
      Getting started? Create a new application     on the Developer Portal.
      Existing application? Go to My apps     to modify your app settings.

Each application is assigned a unique Client ID (Consumer key/API key) and Client
Secret. Please make a note of these values as they will be integrated into your
application config files. Your Client Secret protects your application's security so be sure
to keep it secure!
  ２ Warning

  Do not share your Client Secret value with anyone, and do not pass it in the URL
  when making API calls, or URI query-string parameters, or post in support forums,
  chat, etc.




Step 2: Generate an Access Token
To generate an access token, issue a HTTP POST against accessToken with a Content-
Type header of x-www-form-urlencoded and the following parameters in the request

body:

  https


  https://www.linkedin.com/oauth/v2/accessToken



                                                                                     ﾉ   Expand table


 Parameter       Description                                                                 Required

 grant_type      The value of this field should always be client_credentials                 Yes

 client_id       The Client ID value generated when you registered your application          Yes

 client_secret   The Client Secret value generated when you registered your                  Yes
                 application. All values requiring URL encoding must be encoded. Client
                 secrets can include characters like / , = , + which require URL encoding.


      View the Best Practices for Secure Applications page for more security info.


Sample Request (Secure Approach)
  https


       https


       POST https://www.linkedin.com/oauth/v2/accessToken HTTP/1.1

       Content-Type: application/x-www-form-urlencoded
       grant_type=client_credentials
       client_id={your_client_id}
       client_secret={your_client_secret}




A successful access token request returns a JSON          object containing the following
fields:

        access_token — The access token for the application. This token must be kept

       secure.
        expires_in — Seconds until token expiration.
           The access token has a 30-minute lifespan and must be used immediately. You
           may request a new token once your current token expires.


Sample Response
  JSON


   {
          "access_token": "AQV8...",
          "expires_in": "1800"
   }



For error details, refer the API Error Details section.



Step 3: Make API Requests
Once you've received an access token, you can make API requests by including an
Authorization header with your token in the HTTP call to LinkedIn's API.


Sample Request
  https


   GET https://api.linkedin.com/v2/jobs HTTP/1.1
  Connection: Keep-Alive
  Authorization: Bearer {access_token}




API Error Details
                                                                                      ﾉ   Expand table


 HTTP        ERROR MESSAGE                DESCRIPTION                   RESOLUTION
 STATUS
 CODE

 401         invalid_client_id "Client    Client Authentication         Check whether the right Client
             authentication failed"       failed due to bad client      ID, Client Secret are passed as
                                          credentials passed as         part of the request.
                                          part of the request.

 401         access_denied "This          The developer                 Reach out to the LinkedIn
             application is not           application doesn’t have      Relationship Manager or
             allowed to create            enough permission to          Business Development team to
             application tokens"          generate 2L application       get the necessary access.
                                          token.

 400         invalid_request "A           Grant type in the request     Add grant_type as
             required parameter           is missing. It is a           client_credentials in the
             "grant_type" is              mandatory parameter.          request.
             missing"

 400         invalid_request "A           Client ID in the request is   Pass the Client ID of the
             required parameter           missing. It is a              developer application in
             "client_id" is missing"      mandatory parameter.          request.

 400         invalid_request "A           Client Secret in the          Pass the Client Secret of the
             required parameter           request is missing. It is a   developer application in the
             "client_secret" is           mandatory parameter.          request.
             missing"

 400         invalid_client_id "The       Invalid client ID is passed   Pass the right client ID from the
             passed in client_id is       in the request.               developer application.
             invalid "abcdefghijk""




Feedback
Was this page helpful?      Yes          No


Provide product feedback
Refresh Tokens with OAuth 2.0
05/31/2025


LinkedIn supports programmatic refresh tokens for all approved Marketing Developer Platform
(MDP) partners.



Introduction
Refresh tokens are used to get a new access token when your current access token expires. For
more information, see the OAuth 2.0 RFC     .

LinkedIn offers programmatic refresh tokens that are valid for a fixed length of time. By default,
access tokens are valid for 60 days and programmatic refresh tokens are valid for a year. The
member must reauthorize your application when refresh tokens expire.




When you use a refresh token to generate a new access token, the lifespan or Time To Live
(TTL) of the refresh token remains the same as specified in the initial OAuth flow (365 days),
and the new access token has a new TTL of 60 days.

For example, on:

     Day 1 - Your refresh token has a TTL of 365 days, and your access token has a TTL of 60
     days.
      Day 59 - If you generate a new access token using the refresh token, the access token will
      have a TTL of 60 days and the refresh token will have a TTL of 306 days (365-59=306).
      Day 360- If you generate a new access token, your access token and refresh token will
      both expire in 5 days (365-360=5) and you must get your application reauthorized by the
      member using the authorization flow.


  ７ Note

         Refresh Tokens are useful in minting new Access tokens and allow for seamless
         operations for extended periods of time. However, LinkedIn reserves the right to
         revoke Refresh Tokens or Access Tokens at any time due to technical or policy
         reasons. In such scenarios, the expectation from products leveraging Refresh Tokens
         is to fallback to the standard OAuth flow, and present the login screen to the end
         users.
         To track the usage of refresh tokens, refer to the Developer Portal Tools page.




Step 1: Getting a Refresh Token
Use the Authorization Code Flow to get both a refresh token and access token. If your
application is authorized for programmatic refresh tokens, the following fields are returned
when you exchange the authorization code for an access token:

      refresh_token — Your refresh token for the application. This token must be kept secure.

      refresh_token_expires_in — The number of seconds remaining until the refresh token

      expires. Refresh tokens usually have a longer lifespan than access tokens.
      scope — URL-encoded, space-delimited list of member permissions your application has

      requested on behalf of the user.|


Sample Response

  JSON


  {
    "access_token": "AQXNnd2kXITHELmWblJigbHEuoFdfRhOwGA0QNnumBI8XOVSs0HtOHEU-
  wvaKrkMLfxxaB1O4poRg2svCWWgwhebQhqrETYlLikJJMgRAvH1ostjXd3DP3BtwzCGeTQ7K9vvAqfQK5i
  G_eyS-q-
  y8WNt2SnZKZumGaeUw_zKqtgCQavfEVCddKHcHLaLPGVUvjCH_KW0DJIdUMXd90kWqwuw3UKH27ki5raFD
  PuMyQXLYxkqq4mYU-IUuZRwq1pcrYp1Vv-
  ltbA_svUxGt_xeWeSxKkmgivY_DlT3jQylL44q36ybGBSbaFn-
  UU7zzio4EmOzdmm2tlGwG7dDeivdPDsGbj5ig",
    "expires_in": 86400,
    "refresh_token": "AQWAft_WjYZKwuWXLC5hQlghgTam-tuT8CvFej9-
  XxGyqeER_7jTr8HmjiGjqil13i7gMFjyDxh1g7C_G1gyTZmfcD0Bo2oEHofNAkr_76mSk84sppsGbygwW-
  5oLsb_OH_EXADPIFo0kppznrK55VMIBv_d7SINunt-
  7DtXCRAv0YnET5KroQOlmAhc1_HwW68EZniFw1YnB2dgDSxCkXnrfHYq7h63w0hjFXmgrdxeeAuOHBHnFF
  YHOWWjI8sLLenPy_EBrgYIitXsAkLUGvZXlCjAWl-W459feNjHZ0SIsyTVwzAQtl5lmw1ht08z5Du-
  RiQahQE0sv89eimHVg9VSNOaTvw",
    "refresh_token_expires_in": 525600,
    "scope":"r_basicprofile"

  }




  ７ Note

  Refresh tokens are approximately 500 characters long. We recommend that your
  application stack be made to handle tokens of at least 1000 characters to accommodate
  future expansion plans. This applies to access tokens as well as refresh tokens.



Step 2: Exchanging a Refresh Token for a New Access Token
You can exchange the refresh token for a new access token by making the following HTTP
POST request with a Content-Type header of x-www-form-urlencoded and the following
parameters in the request body:

  POST


  https://www.linkedin.com/oauth/v2/accessToken



                                                                                       ﾉ   Expand table


 Parameter       Description                                                                  Required

 grant_type      The value of this field should always be refresh_token.                      Yes

 refresh_token   The refresh token from Step 1.                                               Yes

 client_id       The Client ID value generated when you registered your application.          Yes

 client_secret   The Client Secret value generated when you registered your application.      Yes




Sample Request

  https


  POST https://www.linkedin.com/oauth/v2/accessToken
  Content-Type: application/x-www-form-urlencoded
  grant_type=refresh_token&refresh_token=AQQOMeCIQMa6-zjU-
  02w8EJW67wPVk3hjJE5x1lZhU013LihKD8i1DpvaAl2jnuP8F1uXMgkm8nzjPfnaJR_kQNOxsLRLZWnAMz
  HMm81S0yQlkBYicw&client_id=861hhm46p48to2&client_secret=gPecS7yqHkyyShvR



A successful request returns a new access token with a new expiration time and the refresh
token.

  JSON


  {
    "access_token": "BBBB2kXITHELmWblJigbHEuoFdfRhOwGA0QNnumBI8XOVSs0HtOHEU-
  wvaKrkMLfxxaB1O4poRg2svCWWgwhebQhqrETYlLikJJMgRAvH1ostjXd3DP3BtwzCGeTQ7K9vvAqfQK5i
  G_eyS-q-
  y8WNt2SnZKZumGaeUw_zKqtgCQavfEVCddKHcHLaLPGVUvjCH_KW0DJIdUMXd90kWqwuw3UKH27ki5raFD
  PuMyQXLYxkqq4mYU-IUuZRwq1pcrYp1Vv-
  ltbA_svUxGt_xeWeSxKkmgivY_DlT3jQylL44q36ybGBSbaFn-
  UU7zzio4EmOzdmm2tlGwG7dDeivdPDsGbj5ig",
    "expires_in": 86400,
    "refresh_token": "AQWAft_WjYZKwuWXLC5hQlghgTam-tuT8CvFej9-
  XxGyqeER_7jTr8HmjiGjqil13i7gMFjyDxh1g7C_G1gyTZmfcD0Bo2oEHofNAkr_76mSk84sppsGbygwW-
  5oLsb_OH_EXADPIFo0kppznrK55VMIBv_d7SINunt-
  7DtXCRAv0YnET5KroQOlmAhc1_HwW68EZniFw1YnB2dgDSxCkXnrfHYq7h63w0hjFXmgrdxeeAuOHBHnFF
  YHOWWjI8sLenPy_EBrgYIitXsAkLUGvZXlCjAWl-W459feNjHZ0SIsyTVwzAQtl5lmw1ht08z5Du-
  RiQahQE0sv89eimHVg9VSNOaTvw",
    "refresh_token_expires_in": 439200,
    "scope":"r_basicprofile"
  }




API Error Details

                                                                                        ﾉ   Expand table


 HTTP       ERROR MESSAGE                    ERROR DESCRIPTION           RESOLUTION
 STATUS
 CODE

 400        invalid_request "The provided    Invalid or expired or       Refresh Token expired or
            authorization grant or refresh   revoked refresh token is    revoked or invalid, hence
            token is invalid, expired or     sent as part of the         reauthenticate the member to
            revoked"                         request.                    generate the new refresh token.

 400        invalid_request "A required      Redirect_URI in the         Pass the Redirect_URI in the
            parameter "redirect_uri" is      request is missing. It is   request to route user back to
            missing"                         mandatory parameter.        correct landing page.

 400        invalid_request "A required      Grant type in the           Add grant_type as
            parameter "grant_type" is        request is missing. It is   "refresh_token" in the request.
HTTP     ERROR MESSAGE                  ERROR DESCRIPTION           RESOLUTION
STATUS
CODE

         missing"                       mandatory parameter.

400      invalid_request "A required    Client ID in the request    Pass the client id of the app in
         parameter "client_id" is       is missing. It is           request.
         missing"                       mandatory parameter.

400      invalid_request "A required    Refresh Token in the        Pass the stored Refresh Token
         parameter "refresh_token" is   request is missing. It is   received as part of initial access
         missing"                       mandatory parameter.        token call.
Developer Portal Tools
10/08/2025


The LinkedIn Developer Portal Token Generator Tool allows a quick and easy method for
generating an access token to make authenticated API calls.



Generate a Token in the Developer Portal
Once a token is generated, users are redirected to the token information page which includes
details like OAuth scopes and token time to live (TTL) for reference during development
activities.

   1. Visit the LinkedIn Developer Portal Token Generator     tool.

   2. Select the app you'd like to generate a token for.

   3. Select OAuth flow and permission scopes.




   4. Member approval
The authenticated member will receive a request for your app to access to their profile.




   5. Token Generation

Once the token is generated, the "Token Details" will be shown along with the token. Click
"Copy token" to paste it into your application code.
Should you wish to verify this an existing token, the Token Inspector tool   is available on the
same page as the token generator.




Developer Portal Token Inspector
LinkedIn's Developer Portal has a token inspector tool to make token validation as simple as
copy and paste. The same Token validation is available through the API or the UI. The OAuth
2.0 token inspector   is accessible from the developer portal under "Docs and Tools" in the
navigation bar.

The tool requires you to select a developer application either from a dropdown or by entering
the client ID if you have more than 10 developer applications. Make sure you have created at
least one developer application or have been added as an Admin team member to a developer
application before using the tool. You may only inspect tokens generated by the selected
developer application.
The tool can also be used to generate a curl request to the token introspection endpoint.
Simply paste a token in the text box, click "Inspect", and use the "Copy cUrl request" button.




OAuth Refresh Token Usage
A table has been added to the bottom of the Analytics Dashboard in the Developer Portal to
track OAuth refresh token usage. It shows the percentage of quota used for generating access
tokens via refresh tokens, the total allowed quota per app per day, and whether the app is
currently Throttled or Not Throttled. The quota resets daily at 00:00 UTC, and a countdown
timer indicates the time left until the next reset.
