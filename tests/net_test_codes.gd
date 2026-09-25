class_name NetTestCodes
extends Object
## M09b: fixed invite codes for the co-op tests (tests/net_test.gd writes the
## list, net_client.gd / net_server_probe.gd use them). Test-only: never on a
## real server.

const C1 := "TEST-AAAA-BBBB-CCCC"
const SHARED := "TEST-DDDD-EEEE-FFFF"
const UNKNOWN := "TEST-GGGG-HHHH-JJJJ"
