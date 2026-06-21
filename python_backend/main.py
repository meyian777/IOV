from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from openai import OpenAI
from dotenv import load_dotenv
import os

from action_engine import ActionEngine
from project_inspector import ProjectInspector

load_dotenv()

client = OpenAI(
    api_key=os.getenv("OPENAI_API_KEY")
)

app = FastAPI(
    title="LabVoice Core",
    version="0.1"
)

# Allow Flutter Web (Chrome) to communicate with FastAPI
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


class ActionRequest(BaseModel):
    action: str


class ChatRequest(BaseModel):
    message: str


PROJECT_PATH = os.getenv(
    "LABVOICE_PROJECT_PATH",
    os.path.join(os.path.dirname(__file__), ".."),
)


@app.get("/")
def root():
    return {
        "status": "online",
        "assistant": "LabVoice"
    }


@app.post("/execute")
def execute_action(request: ActionRequest):
    return ActionEngine.execute(
        request.action
    )


@app.get("/project/inspect")
def inspect_project():
    return ProjectInspector.inspect(PROJECT_PATH)


SYSTEM_PROMPT = """
You are LabVoice.

You are a voice-first operating system.

Your mission is to help developers,
engineers,
business owners,
security professionals,
data professionals,
and organizations.

You are not a generic chatbot.

You can reason,
remember,
execute,
automate,
and orchestrate tools.

Always identify yourself as LabVoice.

Keep responses concise, practical, and action-oriented.
"""

@app.post("/chat")
def chat(request: ChatRequest):

    response = client.responses.create(
        model="gpt-5",
       input=[
    {
        "role": "system",
        "content": SYSTEM_PROMPT
    },
    {
        "role": "user",
        "content": request.message
    }
]
    )

    return {
        "success": True,
        "response": response.output_text
    }
