[![Unix build](https://img.shields.io/github/actions/workflow/status/Kong/kong-plugin/test.yml?branch=master&label=Test&logo=linux)](https://github.com/Kong/kong-plugin/actions/workflows/test.yml)
[![Luacheck](https://github.com/Kong/kong-plugin/workflows/Lint/badge.svg)](https://github.com/Kong/kong-plugin/actions/workflows/lint.yml)

SMART Plugin - Kong plugin for building SMART on FHIR applications
====================

Building real-world clinical applications is challenging. There are several factors to consider, such as integrations, complexity of clinical workflows, compliance and privacy, interoperability, and more. Developing these clinical applications can be both complex and time-consuming. This SMART plugin will help in building SMART on FHIR applications faster, addressing these challenges.

### Key Features
This plugin provides three routes: two for the SMART on FHIR flow and one for getting clinical data from an EHR (Electronic Health Record) FHIR server:
- **applaunch:** This route helps in launching a SMART on FHIR application.
- **authcallback:** During the SMART on FHIR app launch, this route handles the callback flow.
- **clinicaldata:** This route provides the clinical data needed for the application from the FHIR server.

Using this plugin, applications can focus on the business/clinical use case, while the SMART plugin provides all the necessary building blocks and handles the complexities. This enables faster development of innovative clinical applications to solve real clinical problems.

## Table of contents

- [Configuration](#configuration)
- [Examples](#examples)
- [Future Improvements](#future-improvements)
- [Demo Recording](#demo-recording)

## Configuration

This plugin uses two database tables:

- **smart_apps:**: This table stores data and configuration for your SMART on FHIR applications. It contains details for each application.

- **smart_launches:**: This table stores data for each SMART on FHIR launch.

## Steps to Configure the Plugin

- **Register your Application with the EHR (Electronic Health Record) System:**:
Obtain the `client_id` and `client_secret` by registering your application with your EHR.

- **Insert a Record into the `smart_apps` Table:**:
Use the following SQL command to insert a record into the `smart_apps` table:
```
INSERT INTO smart_apps (app_name, issuer, app_launch_url, app_redirect_url, "scope", client_id, client_secret, created_at, updated_at) 
VALUES ('<AppName>', '<FHIRServerURL>', '<AppLaunchUrl>', 'http://localhost:8000/authcallback', 'launch profile openid fhirUser online_access patient/*.*', '<ClientId>', '<ClientSecret>', timezone('UTC'::text, 'now'::text::timestamp(0) with time zone), timezone('UTC'::text, 'now'::text::timestamp(0) with time zone));

```
Here, `http://localhost:8000/authcallback` is the Kong route for the `authcallback`.

- **Create a Service Called `smart_service`**:
Define a new service in Kong named smart_service.

- **Add Routes for the `smart_service`**:
Create the following three routes for the smart_service:

- `launch_route` with the path `/launch`
- `authcallback` with the path `/authcallback`
- `clinicaldata` with the path `/clinicaldata`

- **Enable the SMART Plugin for `smart_service`**:
Enable the SMART plugin for the `smart_service` to activate its functionality.

**Kong Admin API:**
```
curl -X POST http://localhost:8001/services/{serviceName|Id}/plugins \
    --data "name=smart_plugin"
```

## Future Improvements
Here are some future improvements planned for the plugin:

- Use of Caching for Storing Session Details: Instead of using a database to store session details, we plan to implement caching mechanisms for better performance and scalability.

## Demo Recording

[Click here to watch demo recording.](https://www.loom.com/share/e02d0ce9d06a45d1b2b42d9231c79bfa?sid=a462b394-9ef7-4132-8112-af81a79582d0)

