# KasiAI Smart Marketplace Real Update

This version adds a more realistic marketplace flow:

- Product listings can include product photos from Camera or Gallery.
- Product cards show seller profile preview and product details.
- Demand cards show buyer profile preview and matching product count.
- Users can open other users' public profile from marketplace cards.
- Request Deal and Match Deal create Firestore deal records with buyer/farmer profile snapshots.
- Deals show farmer profile, buyer profile, product photo, note, value, commission, and status.
- Deal status can be changed to Confirmed or Completed.

Firestore collections used:

- users
- product_listings
- buying_demands
- deals

Note: product photos are stored as small base64 images in Firestore for school/demo simplicity. For production, use Firebase Storage.
