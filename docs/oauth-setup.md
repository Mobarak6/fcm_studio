# Google sign-in setup (one time)

FCM Studio signs in to Google with two OAuth clients: one for the desktop app and one for the web build. Someone with access to Google Cloud console creates them once for the team. Everyone else only needs to be added as a test user.

## 1. Choose the Google Cloud project that owns the clients

Use any project you control, for example a new one named `fcm-studio-oauth`. Sending is billed to each target Firebase project, not to this one. Listing your Firebase projects is billed to this one, which is free within Google's normal quota.

In that project, open **APIs & Services → Library** and enable **Firebase Management API**. FCM Studio uses it to list the projects you can see.

## 2. Configure the consent screen

1. Open **Google Auth Platform** (the "OAuth consent screen").
2. Under **Audience**, set the user type to **External** and the publishing status to **Testing**.
3. Add each teammate's Google account as a **test user**.

While the app is in Testing, Google ends each sign-in after 7 days. FCM Studio then asks you to use **Sign in again…** in the project menu.

## 3. Create the desktop client

**Clients → Create client → Desktop app**. Name it "FCM Studio desktop", then copy its **Client ID** and **Client secret**. Google does not treat a desktop client secret as confidential, but keep it out of git anyway.

## 4. Create the web client

**Clients → Create client → Web application**. Name it "FCM Studio web".

Under **Authorized JavaScript origins**, add:
- `http://localhost:5050`, for development;
- the URL where the team hosts the web build.

No redirect URI is needed. Copy its **Client ID**.

## 5. Put the IDs in `config/oauth.json`

```bash
cp config/oauth.example.json config/oauth.json
```

Fill in `desktopClientId`, `desktopClientSecret` and `webClientId`, then rebuild. `config/oauth.json` is git-ignored. The app bundles it, and the web build serves it publicly. That is expected, because client IDs are public.

To run the web build in development, use the port the web client allows:

```bash
flutter run -d chrome --web-port 5050
```

## 6. Permissions each teammate needs

To send from a Google account to a Firebase project, the account needs both of these on that project:
- **Firebase Cloud Messaging API Admin**, or Firebase Admin, Editor or Owner, to send;
- **Service Usage Consumer**, or Editor or Owner, because sends are billed to the target project (`x-goog-user-project`).

If either is missing, FCM Studio's error explanation names the role.
