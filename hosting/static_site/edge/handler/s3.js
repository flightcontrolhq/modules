// @ts-check
"use strict";

// Thin wrapper around @aws-sdk/client-s3 with a keep-alive HTTPS agent.
// Lambda@Edge cold starts amortise much better when sockets stay warm.

const {
  S3Client,
  GetObjectCommand,
  HeadObjectCommand,
} = require("@aws-sdk/client-s3");
const { NodeHttpHandler } = require("@smithy/node-http-handler");
const https = require("https");

const agent = new https.Agent({
  keepAlive: true,
  keepAliveMsecs: 86_400_000,
});

class S3Wrapper {
  /**
   * @param {{ region: string }} params
   */
  constructor({ region }) {
    this.client = new S3Client({
      region,
      requestHandler: new NodeHttpHandler({ httpsAgent: agent }),
    });
  }

  /** @param {import("@aws-sdk/client-s3").GetObjectCommandInput} params */
  getObject(params) {
    return this.client.send(new GetObjectCommand(params));
  }

  /** @param {import("@aws-sdk/client-s3").HeadObjectCommandInput} params */
  headObject(params) {
    return this.client.send(new HeadObjectCommand(params));
  }
}

module.exports = S3Wrapper;
