# Development

LinkedIn members are more comfortable trusting your application when you are
transparent about how you will use their data. We recommend following these best
practices to help your application deliver the most value.



Authentication
      Whenever possible, remind the member that they are logged in to your
      application by displaying their name, portrait, and/or account settings somewhere
      on the page.
      Avoid having to log in multiple times. When a member is integrated for multiple
      permissions, combine the permissions into a single request rather than asking the
      member to reauthenticate and grant consent each time.
      Avoid generating an access token for each API call.Cache the member's access
      token after they grant your application access, and do not re-authenticate the
      member unless they log out or the access token expires.
      Make sure you allow the member to log out, and when they do log out, ensure
      you destroy their access token and refresh token, as applicable.
      Validate the member access token using Token Introspection or by calling any API
      before making the access token call.
      Whenever the access token gets expired, make use of the refresh token, if
      applicable, to exchange for a new access token, unless the refresh token has also
      expired or been revoked.
      Reintroduce the member into the authentication flow only when both the access
      token and the refresh token have expired or been revoked.
      If you authorize the member through the JS SDK, do not send the member
      through the REST authorization flow. If you do, users will have to re-authorize your
      application. You can exchange the JS SDK token for an OAuth 2.0 REST access
      token if you want to make REST calls. Otherwise, use the JS SDK token to make
      calls with the JS SDK.

If a member authorizes your application through the REST workflow, it does not mean
they are automatically logged in to the linkedin.com website. You should not assume
that the member has access to resources that are on the LinkedIn website while using
your application.
Error Handling and Logging

System Outages
Due to the nature of cloud APIs, LinkedIn's services are occasionally interrupted or
temporarily unavailable for reasons outside of LinkedIn's control. Assume that any API
call you make to LinkedIn or any third party could potentially fail. Always include error-
handling logic in your requests. See the Errors page for API error codes and messages.


Errors
A 500 Internal Server Error indicates that LinkedIn is experiencing an internal error. If
you continue to receive server errors, record the following details:

     Request: url , method , header , e.g., access_token , body
     Response: header , e.g., x-li-uuid , x-li-fabric , x-li-request-id , body
     Your application configuration, e.g., client_id

If you continue to receive errors, reach out to your partner technical support channel, or
view our Developer Support Knowledge           .




Feedback
Was this page helpful?     ﾂ Yes    ﾄ No


Provide product feedback      | Get help at Microsoft Q&A
Best Practices for Secure Applications
09/03/2025


At LinkedIn, we take the privacy of our members very seriously. When we grant access to APIs,
we expect developers to take member privacy just as seriously as we do. The LinkedIn platform
uses permissions to protect and prevent abuse of our members' information. By using the
OAuth 2.0 authentication protocol, we allow an application to access LinkedIn data while
protecting members' credentials. Because of this protocol, members are ensured that
applications on our platform are easy to use and protect their privacy and security.


  ７ Note

  You should always request the minimal scopes necessary and only request permissions
  that are needed for application functionality.


Ensure your application follows these best practices.



Access Tokens
Using access tokens, you can access a member's private information through the LinkedIn APIs.
To keep access tokens safe:

        Do not store them in insecure or easily accessible locations. Client-side files, such as
        JavaScript or HTML files, should never be used to store sensitive information, as these can
        easily be accessed.
        Do not store access tokens in code files that can be decompiled, such as Native iOS,
        Android, or Windows Application code files.
        When making calls, always pass access tokens over a secure (HTTPS) connection.



API Key and Secret Key
Two pieces of identifiable information are required to make calls to the LinkedIn API: Client ID
(Consumer Key/API key) and Client Secret .

The Client ID is a public identifier of your application. The Client Secret is confidential and
should only be used to authenticate your application and make requests to LinkedIn's APIs.

Both the Client ID and Client Secret are needed to confirm your application’s identity and it is
critical that you do not expose your Client Secret. Follow these suggestions to keep the secret
safe:
     Do not share your access tokens with anyone, and do not pass it in the URL when making
     API calls, or URI query-string parameters, or post in support forums, chat, etc.
     When creating a native mobile application, do not store it locally on a mobile device.
     Do not expose files such as JavaScript or HTML files in client-side code.
     Do not store it in files on a web server that can be viewed externally. For example,
     configuration files, include files, etc.
     Do not store it in log files or error messages.

Remember that when exchanging an OAuth 2.0 authorization code for an access token,
client_secret is passed as part of the request. Make sure you do not expose this request

publicly.
To reset or generate a new client_secret key, refer to the steps mentioned in the FAQ section.



Secure APIs
To prevent others from reading your requests and to prevent man-in-the-middle attacks, all
OAuth 2.0 requests to our authentication servers must be done over HTTPS. Your application
should also be hosted on a secure server, particularly for pages where a member enters private
information (such as their password for your site) and for any URLs where you ask LinkedIn to
redirect the member as part of the OAuth authorization flow.



Phishing Prevention
Cybercriminals often create websites that look and feel authentic but are really just replicas
created to steal user credentials. Educate your users to look for signs to ensure they are
entering credentials for a real LinkedIn application. Note that browsers may look different, and
this may not always be enough to differentiate a legitimate site from a phishing site. Alert
members not to enter credentials when in doubt and to contact you when they suspect
suspicious activity.

LinkedIn has a DigiCert SHA2 Secure Server Certificate (padlock) that can be viewed prior to
the URL in the browser. The base URL hostname is always "https://www.linkedin.com/               ...".
Beware of URLs that try to mimic LinkedIn by using common misspellings or swapping similar
characters such as "1" (one) for "l" (letter 'L'), e.g., "l1inkedIn.com/", or "linked1n.com/".



Cross-Site Request Forgery
To protect against CSRF attacks     , during authorization, you must pass a state parameter. This
should be a unique string value (for each request) that is unique, difficult to guess, and should
not contain private or sensitive information.
Sample State Value
  https


  state=760iz0bjh9gy71asfFqa



On successful authorization, the redirected URL should look like:


Sample Callback URL
  https


  https://OAUTH2_REDIRECT_URI/?code=AUTH_CODE&state=760iz0bjh9gy71asfFqa



Make sure that the state parameter in the response matches the one you passed in your
authorization request. If the state does not match, the request may be a result of CSRF and
should be rejected.


Third-Party Libraries
When using a third-party library to interact with LinkedIn's APIs, make sure that the library is
from a trusted source. Read reviews, look at the code, and do research to make sure the library
is not malicious and does not behave unexpectedly.

LinkedIn does not officially support third-party libraries. Contact that library’s development
team if you have technical questions or concerns.


Frequently Asked Questions
   1. What steps should developers take if the client_secret of their developer app has been
     compromised? or How can developers reset or rotate their client_secret ?
     Answer: Execute the following steps to rotate the client_secret :
      a. In your Developer application, go to the Auth tab. Under the Application Credentials
          section, you’ll find your Client ID and Primary Client Secret.
      b. Click on the Generate a New Client Secret button.
      c. In the confirmation dialog that appears, choose Confirm. Once confirmed, the current
          Primary Client Secret will become the Secondary Client Secret key. Your application
          will now have two active client secret keys.
      d. Replace the old client secret key in your configurations or code with the newly
          generated Primary Client Secret Key. Test the updated configurations/code to ensure
          everything works as expected.
  e. After successful testing, navigate back to the Application Credentials section.
   f. Click the Remove icon next to the Secondary Client Secret Key to delete it.
2. Can I immediately use the client_id and client_secret generated via the Provisioning
  API key to generate a token or load a widget?
  Answer: No. LinkedIn recommends waiting at least 5 minutes after creating a child app
  before using the associated client_id and client_secret for token generation or widget
  loading. This delay ensures that the newly provisioned app is fully registered and available
  across LinkedIn’s systems, helping to prevent potential errors or incomplete initialization.
