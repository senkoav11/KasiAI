# KasiAI Smart Marketplace Pro Update

This version updates the marketplace to behave more like a real marketplace.

## Added

- Product CRUD for post owner
  - Create product
  - Edit own product
  - Delete own product
- Buying demand CRUD for post owner
  - Create demand
  - Edit own demand
  - Delete own demand
- Product photo preview and full screen product photo
- Full screen public user profile photo
- Like/heart on product and demand posts
- Comment system on product and demand posts
- Notification bell on Home page
- Notifications for:
  - Deal request
  - Deal match
  - Deal status change
  - Like
  - Comment
  - Chat message
- Deal chat between buyer and farmer
- Deal status workflow:
  - Requested / Matched
  - Confirmed
  - Completed
- Completed deals hide related product/demand from marketplace lists
- Completed deals remain visible only in Deals tab for buyer and farmer
- Pagination for product posts, demand posts, and deals when more than 10 records

## Firestore collections used

- users
- product_listings
- product_listings/{productId}/likes
- product_listings/{productId}/comments
- buying_demands
- buying_demands/{demandId}/likes
- buying_demands/{demandId}/comments
- deals
- deals/{dealId}/messages
- notifications

## Build note

Gemini API key is not stored in GitHub source code or Flutter app source code.
AI Crop Doctor now uses Firebase Cloud Functions. Store the key in Firebase Secret Manager:

```cmd
firebase functions:secrets:set GEMINI_API_KEY
firebase deploy --only functions
```
