
#include "NetLoadModule.h"

#ifndef NDEBUG
void AssertFail(const char *assert,const char *file,int line)
{
	char buffer[MAX_LINE_LENGTH];

#ifdef DOTRACE
	sprintf(buffer,"Assert failed\nat line %d of %s:\nASSERT(%s);\n",
		line,file,assert);

	TRACE(buffer);
#else
	sprintf(buffer,"Assert failed at line %d of %s:\n\nASSERT(%s);\n\nDebug?",
		line,file,assert);

	if (MessageBox(GlobalData.hLiteStepWnd,buffer,TITLE,MB_YESNO)==IDYES)
		// breakpoint
		DebugBreak();
#endif
}
#endif

#ifdef DOTRACE

DWORD TraceStartTime = 0;

#include <stdio.h>

void Trace(const char *line)
{
	static bool log=true;
	if (!log) return;
	FILE *f;
	f = fopen(TRACE_FILE,"at");
	if (!f) {
		MessageBox(NULL,
			"Couldn't open log file.\nLogging will be turned off.",
			TITLE,ERROR_MESSAGE_FLAGS);
		log = false;
	}
	fprintf(f,"%10d %s\n",GetTickCount()-TraceStartTime,line);
	fclose(f);
}

void TraceLastError(const char *file,int line)
{
	char buffer[256];
	sprintf(buffer,"System error at line %d of %s:",line,file);
	Trace(buffer);
	FormatMessage(FORMAT_MESSAGE_FROM_SYSTEM,NULL,GetLastError(),NULL,buffer,256,NULL);
	Trace(buffer);
}

#endif

