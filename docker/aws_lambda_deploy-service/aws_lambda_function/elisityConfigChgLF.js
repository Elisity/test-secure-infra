const https = require("https");

// retry REST call to eSaaS if auth fails or API-GW goes-down
const retryCount = process.env.retryCount || 3;  // set it to -1 for  NO-RETRY
const retryWaitMillis = process.env.retryWsitMillis || 10000;
const s3Bucket = process.env.s3Bucket;  // e.g: com.elisity.custExtId
const apiGwHost = process.env.apiGwHost;  // API-GW
const apiGwPort = process.env.apiGwPort;
const cloudConfigSvcPath = process.env.cloudConfigSvcPath;
const awsProfile = process.env.awsProfile;
const kafkaTopic = "elisityCloudEnterpriseAssetTopic";
let finalErrorMsg = '';

const sleep = (milliseconds) => {
    console.log(`Sleep wait ${milliseconds} milliseconds`);
    return new Promise(resolve => setTimeout(resolve, milliseconds));
};

async function getCred() {
    console.log("getCred() - Going to fetch data from S3. ");
    const AWS = require('aws-sdk');
    if (awsProfile) {
        // awsProfile needed only for testing locally from desktop
        console.log(`getCred() - profile=${awsProfile}`);
        AWS.config.credentials = new AWS.SharedIniFileCredentials({profile: awsProfile});
    }

    const s3 = new AWS.S3();
    const params =
        {
            Bucket: s3Bucket,
            Key: '/elisity/cred/lambda-apigw'
        };

    try {
        const data = await s3.getObject(params).promise();
        console.log("getCred() - Done fetching data from S3.");
        return data.Body.toString();
    } catch (e) {
        let emsg = `getCred() - Exception while reading data from S3.  ${e.message}`;
        finalErrorMsg = emsg;
        console.log(emsg);
        throw new Error(emsg);
    }
}

async function getAuthToken() {
    console.log("getAuthToken() - Going to get Auth Token.");
    let token = '';
    let credData = await getCred();
    console.log("getAuthToken() - Got S3 data.");
    if (credData) {
        console.log("getAuthToken() - cred is available");
        let cred = JSON.parse(credData);
        console.log("getAuthToken() - JSON Parse OK");
        if (cred) {
            token = cred["access_token"];
            console.log("getAuthToken() - Extracted token.");
            return token;
        }
    }
    console.log("getAuthToken() - Unable to get Auth Token");
    finalErrorMsg = 'getAuthToken() - Unable to get Auth Token';
    throw new Error("getAuthToken() - Unable to get Auth Token");
}

function buildRestPayload(eventJson) {
    let resourceId = null;
    let msgTypeValue = 0;

    try {
        resourceId = eventJson["resources"][0].split('/').slice(-1)[0];

        /*
        if (resourceId.includes("vpc")) {
            msgTypeValue = 11;
        } else if (resourceId.includes("subnet")) {
            msgTypeValue = 12;
        }*/
        msgTypeValue = 85;
    } catch (e) {
        let emsg = `buildRestPayload() - Event parsing failed. Invalid event ${e}`;
        console.log(emsg);
        finalErrorMsg = emsg;
        throw new Error(emsg);
    }

    if (msgTypeValue === 0) {
        console.log("buildRestPayload() - Event should be ignored - not a state chg or tag chg event.");
    }
    return {key: resourceId, msg: {MsgType: msgTypeValue, MsgOp: 3, MsgBody: eventJson}};
}

async function postMsgToEsaas(eventStr) {
    console.log("postMsgToEsaas() - Going to send the event msg to eSaaS via REST call");
    let payloadJson = {};
    try {
        payloadJson = buildRestPayload(eventStr);
        console.log(`postMsgToEsaas() payload: ${JSON.stringify(payloadJson)}`);
        if (payloadJson && payloadJson.msg.MsgType === 0) {
            console.log("postMsgToEsaas() - Ignoring event.");
            return true;
        }
    } catch (e) {
        let emsg = `postMsgToEsaas() - Event parsing failed. Invalid event ${e}`;
        console.log(emsg);
        finalErrorMsg = emsg;
        throw new Error(emsg);
    }
    console.log("postMsgToEsaas() - Msg Key (Instance-ID) " + payloadJson.key);
    const payloadStr = JSON.stringify(payloadJson.msg);

    let token = await getAuthToken();

    const options = {
        host: apiGwHost,
        port: apiGwPort,
        path: `${cloudConfigSvcPath}?topic=${kafkaTopic}&key=${payloadJson.key}`,
        method: 'POST',
        rejectUnauthorized: false,
        headers: {
            'Content-Type': 'application/json',
            'Content-Length': Buffer.byteLength(payloadStr),
            'Authorization': `Bearer ${token}`
        }
    };
    console.log("postMsgToEsaas() - initialized https post options");

    try {
        return new Promise(function (resolve, reject) {
            console.log("postMsgToEsaas() - invoking https call to eSaaS");
            let req = https.request(
                options, (res) => {

                    let buffers = [];

                    res.on('error', e => {
                        finalErrorMsg = e;
                        console.log(`postMsgToEsaas() - RES.on.Error() - ${e}`);
                        reject(e);
                    });

                    res.on('data', buffer => buffers.push(buffer));

                    res.on(
                        'end',
                        () => {
                            let resp = Buffer.concat(buffers).toString();
                            console.log(`postMsgToEsaas() - Got response from eSaaS: ${resp}`);

                            if (res.statusCode === 200) {
                                console.log(`postMsgToEsaas() - eSaaS res status OK: ${res.statusCode}`);
                                resolve(resp);
                            } else {
                                console.log(`postMsgToEsaas() - eSaaS res status NOT-OK: ${res.statusCode}`);
                                reject(resp);
                            }
                        }
                    );
                }
            );

            req.on('error', e => {
                finalErrorMsg = e;
                console.log(`postMsgToEsaas() - REQ.on.Error() - ${e}`);
                reject(e);
            });
            req.write(payloadStr);  // payload for eSaaS service
            req.end();        // close POST request
        });

    } catch (e) {
        finalErrorMsg = e.message;
        let emsg = `postMsgToEsaas() - Got Exception. Could not send msg to eSaaS ${e}`;
        console.log(emsg);
        throw new Error(emsg);
    }
}

exports.handler = async (eventJson) => {
    // ***  NOTE: event should be >>JSON Object<<,  not STRING ***
    console.log(`Handler received an event: ${JSON.stringify(eventJson)}`);
    let retStatus = false;

    for (let i = 0; i < retryCount; i++) {
        await postMsgToEsaas(eventJson).then(
            () => {
                retStatus = true;
                console.log(`Handler() is exiting Retry loop ${i + 1}`);
                i = retryCount;
            }).catch(
            async e => {
                finalErrorMsg = e.message;
                console.log(`Handler() - Send msg to eSaaS failed. ${e}. Retry #${i + 1} after wait`);
                await sleep(retryWaitMillis);
            });
    }
    console.log(`Return Status: ${retStatus}`);
    if (!retStatus) throw new Error(`Lambda Fn call failed: ${finalErrorMsg}`);
    return retStatus;
};
