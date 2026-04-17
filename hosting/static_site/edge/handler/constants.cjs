// Shared constants for the static-site Lambda@Edge handler.
//
// MAIN_FOLDER and VERSIONS_FOLDER define the S3 layout convention:
//   s3://<bucket>/<MAIN_FOLDER>/...           production deployment
//   s3://<bucket>/<VERSIONS_FOLDER>/<id>/...  versioned/preview deployment
//
// The active prefix for each request is selected from the x-fc-deployment-id
// custom origin header (set by the CloudFront Function in filesystem_previews
// mode, or by the static origin header config in filesystem mode).

const MAIN_FOLDER = "main";
const VERSIONS_FOLDER = "versions";

module.exports = { MAIN_FOLDER, VERSIONS_FOLDER };
