// Lambda Function for Refreshing Auth Tokens
// Suresh T, July 2019

const https = require("https");

const retryCount = process.env.retryCount || 5;  // set it to -1 for  NO-RETRY
const retryWaitMillis = process.env.retryWsitMillis || 10000;

const s3Bucket = process.env.s3Bucket;  // e.g: com.elisity.custExtId
const apiGwHost = process.env.apiGwHost;  // API-GW
const apiGwPort = process.env.apiGwPort;
const apiGwPath = process.env.apiGwPath;
// noinspection JSUnusedLocalSymbols
const apiGwAuthRefreshPath = process.env.apiGwAuthRefreshPath;
const awsProfile = process.env.awsProfile;
let finalErrorMsg = '';

const sleep = (milliseconds) => {
    console.log(`Sleep wait ${milliseconds} milliseconds`);
    return new Promise(resolve => setTimeout(resolve, milliseconds));
};

async function fetchCredFromS3() {
    console.log("fetchCredFromS3() - Going to fetch data from S3. ");
    const AWS = require('aws-sdk');
    if (awsProfile) {
        // awsProfile needed only for testing locally from desktop
        console.log(`fetchCredFromS3() - profile=${awsProfile}`);
        AWS.config.credentials = new AWS.SharedIniFileCredentials(
            {profile: awsProfile});
    }

    const s3 = new AWS.S3();
    const params =
        {
            Bucket: s3Bucket,
            Key: '/elisity/cred/lambda-apigw'
        };

    try {
        const data = await s3.getObject(params).promise();
        console.log("fetchCredFromS3() - Done fetching data from S3.");
        return data.Body.toString();
    } catch (e) {
        console.log("fetchCredFromS3() - Exception while reading data from S3. "
            + e.message);
        throw new Error(
            `fetchCredFromS3() - Could not retrieve data from S3: ${e.message}`);
    }
}

async function saveCredToS3(cred) {
    console.log("saveCredToS3() - Going to save data to S3.");
    const AWS = require('aws-sdk');
    if (awsProfile) {
        // awsProfile needed only for testing locally from desktop
        console.log(`saveCredToS3() - profile=${awsProfile}`);
        AWS.config.credentials = new AWS.SharedIniFileCredentials(
            {profile: awsProfile});
    }

    const s3 = new AWS.S3();
    const params =
        {
            Bucket: s3Bucket,
            Key: '/elisity/cred/lambda-apigw',
            Body: JSON.stringify(cred)
        };

    try {
        let saveResult = await s3.putObject(params).promise();
        console.log("saveCredToS3() - Done saving data to S3.");
        return saveResult;
    } catch (e) {
        console.log(
            "saveCredToS3() - Exception while saving data to S3. " + e.message);
        finalErrorMsg = e.message;
        throw new Error(
            `"saveCredToS3() - Could not save data to S3: ${e.message}`);
    }
}

async function getCred() {
    console.log("getCred() - Going to get cred info");
    let credData = await fetchCredFromS3();

    if (credData) {
        console.log("getCred() - cred is available");
        let cred = JSON.parse(credData);
        console.log("getCred() - credData JSON Parse OK");
        if (cred) {
            return cred;
        }
    }
    console.log("getCred() - Unable to get Auth information");
    finalErrorMsg = 'Unable to get Auth information';
    throw new Error("getCred() - Unable to get Auth information");
}

async function getNewTokenFromEsaas(cred) {
    console.log("getNewTokenFromEsaas() - Going to get new token from eSaaS.");
    const options = {
        host: apiGwHost,
        port: apiGwPort,
        path: apiGwPath,
        method: 'GET',
        rejectUnauthorized: false,
        auth: `${cred["uid"]}:${cred["pwd"]}`
    };
    console.log("getNewTokenFromEsaas() - Initialized https post options");

    try {
        return new Promise(function (resolve, reject) {
            console.log("getNewTokenFromEsaas() - Invoking https call to eSaaS");
            let req = https.request(
                options, (res) => {

                    let buffers = [];

                    res.on('error', e => {
                        finalErrorMsg = e;
                        console.log(`getNewTokenFromEsaas() - RES.on.Error() - ${e}`);
                        reject(e)
                    });

                    res.on('data', buffer => {
                        console.log("getNewTokenFromEsaas() - Receiving POST response");
                        buffers.push(buffer)
                    });

                    res.on(
                        'end',
                        () => {
                            let resp = Buffer.concat(buffers).toString();
                            console.log(
                                `getNewTokenFromEsaas() - Got response from eSaaS`);

                            if (res.statusCode === 200) {
                                console.log(
                                    `getNewTokenFromEsaas() - eSaaS res status OK: ${res.statusCode}`);
                                resolve(resp);
                            }
                            else {
                                console.log(
                                    `getNewTokenFromEsaas() - eSaaS res status NOT-OK: ${res.statusCode}`);
                                console.log(
                                    `getNewTokenFromEsaas() - eSaaS res content: ${resp}`);
                                reject(resp);
                            }
                        }
                    );
                }
            );
            req.on('error', e => {
                finalErrorMsg = e;
                console.log(`getNewTokenFromEsaas() - REQ.on.Error() - ${e}`);
                reject(e)
            });
            req.end();
        });
    } catch (e) {
        console.log("getNewTokenFromEsaas() - Got Exception" + e.message);
        finalErrorMsg = e.message;
        throw new Error(
            `getNewTokenFromEsaas() - Could not refresh TOKEN from eSaaS: ${e.message}`);
    }
}

async function refreshAuthToken() {
    console.log("refreshAuthToken() - Going to refresh Auth Token");

    //  Auth Refresh logic:
    //  Assume Access token expiry is Ta in minutes and Refresh token expiry in Tr minutes
    //  1) refresh access_token every (Ta - 5) minutes using Refresh_Token
    //  2) And get a new Refresh_Token every (Tr - Ta - 5) minutes
    //  We will save the next-renewal of refresh_token in the S3 along with the tokens
    //  if refresh_token_exp_epoc_minutes_in_db - current_time_in_UTC_minutes > (Ta - 5) min,
    //    refresh using refresh_token
    //  else
    //    refresh using uid/pwd

    try {
        let cred = await getCred();
        let tokenResp = null;
        await getNewTokenFromEsaas(cred).then(r => tokenResp = r).catch(e => {
            finalErrorMsg = e.message;
            console.log("refreshAuthToken() - getTokenFromEsaas Failed. " + e);
            throw new Error(e)
        });

        console.log(`refreshAuthToken() - Got response for Token refresh`);
        let tr = JSON.parse(tokenResp);
        console.log("refreshAuthToken() - Token Resp JSON parsing OK");

        if ("access_token" in tr.data[0]) {
            cred["access_token"] = tr.data[0].access_token;

            console.log("refreshAuthToken() - Extracted access_token successfully");
        }
        else {
            console.log("refreshAuthToken() - Could not find access_token in resp");
        }

        if ("refresh_token" in tr.data[0]) {
            cred["refresh_token"] = tr.data[0].refresh_token;
            console.log("refreshAuthToken() - Extracted refresh_token successfully");

            let refreshTokenExpInMinutes = 8 * 60;  // 480 minutes (8 hours)
            try {
                refreshTokenExpInMinutes = tr.data[0]["refresh_expires_in"] / 60;
            } catch (e) {
                console.log(
                    `Invalid value in response for 'refresh_expires_in'. ${e}. Will use default value`)
            }

            cred["refresh_token_exp_utc_epoc_minutes"] = Math.floor(Date.now() / 60000)
                + refreshTokenExpInMinutes;

            let accessTokenExpInMinutes = 30;  // 30 minutes
            try {
                accessTokenExpInMinutes = tr.data[0]["expires_in"] / 60;
            } catch (e) {
                console.log(
                    `Invalid value in response for 'expires_in'. ${e}. Will use default value`)
            }

            cred["access_token_exp_utc_epoc_minutes"] = Math.floor(Date.now() / 60000)
                + accessTokenExpInMinutes;
        }
        else {
            console.log("refreshAuthToken() - Could not find refresh_token in resp");
        }
        return saveCredToS3(cred);
    } catch (e) {
        console.log(`refreshAuthToken() - Could not refresh token ${e}`);
        finalErrorMsg = e.message;
        throw new Error(`refreshAuthToken() - Could not refresh token ${e}`);
    }
}

exports.handler = async (eventJson) => {

    //  *** NOTE: event should be >>JSON Object<<,  not STRING ***
    console.log(`Handler received an event: ${JSON.stringify(eventJson)}`);

    let retStatus = false;
    for (let i = 0; i < retryCount; i++) {
        await refreshAuthToken(eventJson).then(
            () => {
                retStatus = true;
                console.log(`Handler() is exiting Retry loop ${i + 1}`);
                i = retryCount;
            }).catch(
            async e => {
                console.log(`Handler() - POST to eSaaS failed. ${e}. Retry #${i
                + 1} after wait`);
                finalErrorMsg = e.message;
                await sleep(retryWaitMillis);
            });
    }
    console.log(`Return Status: ${retStatus}`);
    if (!retStatus) {
        throw new Error(
            `TokenRefreshLF lambda call failed: ${finalErrorMsg}`);
    }
    return retStatus;
};
