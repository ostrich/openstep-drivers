/* MIT license. Read-only native system information. */
#ifndef OS42_AGENT_INFO_H
#define OS42_AGENT_INFO_H
int agent_info_request(const char *command,char *result,unsigned capacity,const char **error);
#endif
