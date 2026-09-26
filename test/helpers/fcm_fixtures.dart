const successBody = '{"name":"projects/demo-project/messages/0:1"}';

const unregisteredBody =
    '{"error":{"code":404,"message":"Requested entity was not found.","status":"NOT_FOUND",'
    '"details":[{"@type":"type.googleapis.com/google.firebase.fcm.v1.FcmError","errorCode":"UNREGISTERED"}]}}';

const invalidArgumentBody =
    '{"error":{"code":400,"message":"Invalid value at \'message.data[0].value\' (TYPE_STRING), 42",'
    '"status":"INVALID_ARGUMENT","details":[{"@type":"type.googleapis.com/google.rpc.BadRequest",'
    '"fieldViolations":[{"field":"message.data[0].value",'
    '"description":"Invalid value at \'message.data[0].value\' (TYPE_STRING), 42"}]}]}}';

const serviceDisabledBody =
    '{"error":{"code":403,"message":"Firebase Cloud Messaging API has not been used in project '
    '123456789012 before or it is disabled.","status":"PERMISSION_DENIED","details":[{"@type":'
    '"type.googleapis.com/google.rpc.ErrorInfo","reason":"SERVICE_DISABLED","domain":"googleapis.com"}]}}';
