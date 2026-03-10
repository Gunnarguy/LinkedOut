# Overview

The LinkedIn API uses OAuth 2.0       for member (user) authorization and API
authentication. Applications must be authorized and authenticated before they can
fetch data from LinkedIn or get access to LinkedIn member data.

There are two types of Authorization Flows available:

      Member Authorization (3-legged OAuth)
      Application Authorization (2-legged OAuth)

Depending on the type of permissions your integration will require, follow one of the
authorization flows to get started.


  ７ Note

        There are several third-party libraries in the open source community which
        abstract the OAuth 2.0 authentication process in every major programming
        language.
        LinkedIn does not support TLS 1.0.




Member Authorization (3-legged OAuth Flow)
The Member Authorization grants permissions to your application by a LinkedIn
member to access the member’s resources on LinkedIn. Your application has no access
to these resources without member approval. The Member Auth uses the 3-legged
OAuth code flow. For step-by-step instructions on how to implement 3-legged OAuth,
see Authorization Code Flow (3-legged OAuth) page.


   Tip

  When to use 3-legged OAuth
  Use this flow if you are requesting access to a member's account to use their data
  and make requests on their behalf. This is the most commonly used permission
  type across LinkedIn APIs. Open permissions available to all applications are of this
  type such as r_liteprofile , r_emailaddress , and w_member_social .
Member Auth Permissions
Member Authorization Permissions are granted by a LinkedIn member to access
members resources on LinkedIn. Permissions are authorization consents to access
LinkedIn resources. The LinkedIn platform uses permissions to protect and prevent
abuse of member data. Your application must have the appropriate permissions before
it can access data. To see the list of permissions, descriptions and access details, refer to
Getting Access to LinkedIn APIs page.



Application Authorization (2-legged OAuth
Client Credential Flow)
Application Authorization or using 2-Legged OAuth grants permissions to your
application to access protected LinkedIn resources. If you are accessing APIs that are not
member specific, use this flow. Not all APIs support Application Authorization. For
example, Marketing APIs you must use Member Authorization explained above. For
step-by-step instructions on how to implement 2-legged OAuth, see Client Credential
Flow (2-legged OAuth) page.


  ７ Note

  Always request the minimal permission scopes necessary for your use case.



Application Auth Permissions
Application Authorization Permissions are granted to applications to access LinkedIn
protected resources. To see the list of permissions, descriptions and access details, refer
to Getting Access to LinkedIn APIs page.


Sample Application
You can explore the OAuth Sample Applications that enables you to try out RESTful
OAuth calls to the LinkedIn Authentication server. The sample app is available in Java.

Additionally, you can also explore the Marketing Sample Application.
