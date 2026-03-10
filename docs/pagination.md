# Pagination

API calls that return a large number of entities are broken up into multiple pages of
results. You might need to make multiple API calls with slightly varied paging
parameters to iteratively collect all the data you are trying to gather.

Use the following query parameters to paginate through results:



Parameters
 Name     Description                                                                  Default

 start    The index of the first item you want results for.                            0

 count    The number of items you want included on each page of results. There could   10
          be fewer items remaining than the value you specify.


To paginate through results, begin with a start value of 0 and a count value of N. To
get the next page, set start value to N, while the count value stays the
same. Subsequent pages start at 2N, 3N, 4N, and so on.



Samples

Sample Request

  https


  GET https://api.linkedin.com/v2/{service}




Sample Response

  JSON


  "elements": [
      {"Result #0"},
      {"Result #1"},
      {"Result #2"},
      {"Result #3"},
      {"Result #4"},
      {"Result #5"},
          {"Result #6"},
          {"Result #7"},
          {"Result #8"},
          {"Result #9"}
  ],
  "paging": {
      "count": 10,
      "start": 0
  }




Sample Request

  https


  GET https://api.linkedin.com/v2/{service}?start=10&count=10




Sample Response

  JSON


  "elements": [
      {"Result #10"},
      {"Result #11"},
      {"Result #12"},
      {"Result #13"},
      {"Result #14"},
      {"Result #15"},
      {"Result #16"},
      {"Result #17"},
      {"Result #18"},
      {"Result #19"}
  ],
  "paging": {
      "count": 10,
      "start": 10
  }




End of the Dataset
You have reached the end of the dataset when your response contains fewer elements in
the entities block of the response than your count parameter request.




Feedback
Was this page helpful?     ﾂ Yes    ﾄ No


Provide product feedback      | Get help at Microsoft Q&A
Rate Limiting
08/20/2025


To prevent abuse and ensure service stability, all API requests are rate limited. Rate limits
specify the maximum number of API calls that can be made in a 24 hour period. These limits
reset at midnight UTC    every day.

There are two kinds of limits that affect your application:

     Application — The total number of calls that your application can make in a day.
     Member — The total number of calls that a single member per application can make in a
     day.


  ７ Note

  The term Member refers to a LinkedIn user whose token is used to initiate API calls from
  the developer application. For example, a partner is responsible for managing multiple
  members. This member-level designation indicates the permissible number of API calls the
  partner can initiate from their application on behalf of a member token.


Rate limited requests will receive a 429 response. In rare cases, LinkedIn may also return a 429
response as part of infrastructure protection. API service will return to normal automatically.

Your application's daily rate limit varies based on which API endpoint you are using. Standard
rate limits are not published in documentation. You can look up the rate limit of any endpoint
your app has access to through the Developer Portal      . Select your app from the list and
navigate to its Analytics tab. This page will only show usage and rate limits for endpoints you
have made at least 1 request to today(UTC). If you want to look up a rate limit for an endpoint
not listed in your app's Analytics page, make 1 test call to that endpoint and refresh the
Analytics page.
Rate Limit Alert Notifications
Developer Admins will receive email alerts when their application exceeds 75% of the assigned
rate limit quota.


  ） Important

  Alerts are triggered only on application-level threshold breaches, not on member-level
  or combined member+app-level breaches.


     Alert Timing: Alerts are not sent in real-time. There is an expected delay of
     approximately 1–2 hours after the threshold is reached.

     Additional Alerts: If another API endpoint breaches the threshold later in the same day, a
     new alert will be sent, even if a previous alert was already delivered.
