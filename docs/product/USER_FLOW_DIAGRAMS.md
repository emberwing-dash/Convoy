# CONVOY USER FLOW ARCHITECTURE & DIAGRAMS

**Convoy iOS Application Architecture Audit**  
**Document:** `docs/product/USER_FLOW_DIAGRAMS.md`  
**Platform:** Native iOS / SwiftUI / Supabase  
**Inspection Date:** November 2026  

---

## 1. Visual Legend & Status Taxonomy

All diagrams in this document employ a standardized color and border taxonomy to reflect actual code implementation status:

- <span style="color:#10b981;font-weight:bold;">Green / Solid Border:</span> **Fully Implemented & Production-Connected**
- <span style="color:#f59e0b;font-weight:bold;">Orange / Dashed Border:</span> **Partially Implemented / Contains Bugs or Gaps**
- <span style="color:#ef4444;font-weight:bold;">Red / Dotted Border:</span> **Completely Missing / Mocked / Non-Functional**

---

## 2. Diagram 1: Crew Creation & Management Journey

```mermaid
flowchart TD
    A([User Opens Crew Tab]) --> B[CrewView: Check app.crews]
    B -->|Empty| C[EmptyCrewView CTA: 'Create a Crew']
    B -->|Populated| D[Crew List Carousel & Pending Invites]
    C --> E[NewCrewView: Enter Name, Motto, City, Avatar]
    D -->|Tap '+' Button| E
    E --> F{Validate Form: Name non-empty?}
    F -->|No| E
    F -->|Yes| G[Tap 'Create Crew': AppState.createCrew]
    G --> H[Upload Avatar to Supabase Storage]
    H --> I[INSERT into 'crews' table]
    I --> J[INSERT into 'crew_members' table role='admin']
    J --> K[CrewDetailView: Renders Members & Stats]
    
    K --> L[Tap 'Invite Riders']
    L --> M[CrewInviteView: User Search & Multi-Select]
    
    K -.->|MISSING| N[Remove Member Option]
    K -.->|MISSING| O[Leave Crew Option]
    K -.->|MISSING| P[Edit Crew Details / Avatar]
    K -.->|MISSING| Q[Disband / Delete Crew]

    classDef done fill:#064e3b,stroke:#10b981,stroke-width:2px,color:#fff;
    classDef partial fill:#78350f,stroke:#f59e0b,stroke-width:2px,stroke-dasharray: 5 5,color:#fff;
    classDef missing fill:#7f1d1d,stroke:#ef4444,stroke-width:2px,stroke-dasharray: 2 2,color:#fff;

    class A,B,C,D,E,F,G,H,I,J,K,L,M done;
    class N,O,P,Q missing;
```

---

## 3. Diagram 2: Crew Member Invitation & Acceptance Journey

```mermaid
flowchart TD
    Admin([Crew Admin in CrewDetailView]) --> SearchUI[CrewInviteView: Enter Search Query]
    SearchUI --> QueryDB[Supabase: SELECT profiles WHERE username ILIKE query]
    QueryDB --> SelectUsers[Admin selects user cards into badge tray]
    SelectUsers --> SendInvites[Tap 'Send Invites': AppState.inviteUsersToCrew]
    SendInvites --> InsertDB[INSERT into crew_members status='pending']
    InsertDB --> NotifDB[INSERT into notifications type='crew_invite']
    
    NotifDB --> Invitee([Invited User Opens App])
    Invitee --> Badge[Crew Tab Red Badge & Pending Card]
    Badge --> ResponseChoice{Invitee Response}
    
    ResponseChoice -->|Tap 'Accept'| AcceptOp[UPDATE crew_members SET status='accepted']
    AcceptOp --> RefreshRoster[Crew appears in Invitee Active Crews List]
    
    ResponseChoice -->|Tap 'Decline'| DeclineOp[UPDATE crew_members SET status='declined']
    DeclineOp --> DismissCard[Card removed from UI]

    classDef done fill:#064e3b,stroke:#10b981,stroke-width:2px,color:#fff;
    class Admin,SearchUI,QueryDB,SelectUsers,SendInvites,InsertDB,NotifDB,Invitee,Badge,ResponseChoice,AcceptOp,RefreshRoster,DeclineOp,DismissCard done;
```

---

## 4. Diagram 3: Trip Planning Journey (From Scratch / Home Hub)

```mermaid
flowchart TD
    Home([Home Hub: Tap 'Plan a Ride']) --> Step1[PlanWhoView: Select Participant Mode]
    Step1 -->|Select 'Just Me'| WhoDone[app.selectedCrew = nil]
    Step1 -->|Select 'With a Crew'| WhoCrew[app.selectedCrew = crew]
    Step1 -->|Select 'With Friends'| WhoFriends[app.selectedFriends = [friends]]
    
    WhoDone --> Step2[PlanDetailsView: Empty inputs]
    WhoCrew --> Step2
    WhoFriends --> Step2
    
    Step2 --> EnterDetails[User enters Ride Name, Date, Start/End addresses]
    EnterDetails --> Step3[PlanMapView: Confirm Coordinates on MapKit Canvas]
    Step3 --> Step4[PlanRoutesView: Calibrate Multi-Route Alternatives]
    Step4 --> Step5[PlanReviewView: Pacing Profile & Stop Configurator]
    Step5 --> Step6[PlanCreatedView: Displays 6-char Code & QR]
    
    Step6 --> TapDone[Tap 'Done' / 'View Ride': finishPlan]
    TapDone --> InsertRide[INSERT into 'rides' table]
    InsertRide --> InsertCreator[INSERT creator into 'ride_members' status='accepted']
    
    InsertCreator -.->|CRITICAL BUG: Discarded!| DropCrew[selectedCrew & selectedFriends DISCARDED]
    InsertCreator -.->|CRITICAL BUG: Discarded!| NoInvites[Zero Invites Dispatched to Selected Crew/Friends]

    classDef done fill:#064e3b,stroke:#10b981,stroke-width:2px,color:#fff;
    classDef partial fill:#78350f,stroke:#f59e0b,stroke-width:2px,stroke-dasharray: 5 5,color:#fff;
    classDef missing fill:#7f1d1d,stroke:#ef4444,stroke-width:2px,stroke-dasharray: 2 2,color:#fff;

    class Home,Step1,WhoDone,WhoCrew,WhoFriends,Step2,EnterDetails,Step3,Step4,Step5,Step6,TapDone,InsertRide,InsertCreator done;
    class DropCrew,NoInvites missing;
```

---

## 5. Diagram 4: Trip Planning Journey (From Discover Route Handoff)

```mermaid
flowchart TD
    Discover([User browsing Discover Hub]) --> Card[Taps Curated Route Card]
    Card --> Detail[RouteDetailSheet: Elevation, Surface, Curvature, Calibrated ETA]
    Detail --> PlanCTA[Tap 'Plan this ride']
    
    PlanCTA --> Handoff[Stage 6A Handoff: Pre-populate Discover Data]
    Handoff --> Step1[PlanWhoView: Select Solo / Crew / Friends]
    Step1 --> Step2[PlanDetailsView: Pre-filled Title, Origin, Destination, Distance]
    Step2 --> Step3[PlanMapView: Route pre-plotted on map]
    Step3 --> Step4[PlanRoutesView: Selected Discover variant highlighted]
    Step4 --> Step5[PlanReviewView: Pacing profile & stops initialized]
    Step5 --> Step6[PlanCreatedView: Unique Join Code Generated]
    Step6 --> Save[finishPlan: Persist to Supabase rides table]

    classDef done fill:#064e3b,stroke:#10b981,stroke-width:2px,color:#fff;
    class Discover,Card,Detail,PlanCTA,Handoff,Step1,Step2,Step3,Step4,Step5,Step6,Save done;
```

---

## 6. Diagram 5: Join-by-Code & Preview Journey

```mermaid
flowchart TD
    Rider([Prospective Rider]) --> EntryChoice{Entry Method}
    EntryChoice -->|Manual| TapJoin[Home: Tap 'Join with Code']
    EntryChoice -->|Deep Link| OpenLink[convoy://join/CODE]
    
    TapJoin --> JoinInput[JoinCodeView: 6-cell Alphanumeric Input]
    OpenLink --> JoinInput
    
    JoinInput --> AutoLookup{Input length == 6?}
    AutoLookup -->|Yes| Query[AppState.findRide: Supabase lookup]
    
    Query -->|Not Found| Alert[Show 'Invalid Code' Red Alert]
    Query -->|Found| PreviewCard[Display Ride Preview Card: Title, Organiser, Distance, Time]
    
    PreviewCard --> CheckJoined{Already Member or Pending?}
    CheckJoined -->|Already Member| DisabledJoined['Already Joined This Ride']
    CheckJoined -->|Pending| DisabledPending['Request Pending Approval']
    CheckJoined -->|Eligible| RequestCTA[Tap 'Request to Join']
    
    RequestCTA --> PostRequest[INSERT into 'ride_join_requests' status='pending']
    PostRequest --> PostNotif[INSERT into 'notifications' for Organiser]
    PostNotif --> SuccessUI[Update Button: 'Request Sent - Waiting for Approval']

    classDef done fill:#064e3b,stroke:#10b981,stroke-width:2px,color:#fff;
    class Rider,EntryChoice,TapJoin,OpenLink,JoinInput,AutoLookup,Query,Alert,PreviewCard,CheckJoined,DisabledJoined,DisabledPending,RequestCTA,PostRequest,PostNotif,SuccessUI done;
```

---

## 7. Diagram 6: Organizer Request Approval Journey

```mermaid
flowchart TD
    Organiser([Organiser Device]) --> Bell[Home Header: Tap Notification Bell]
    Bell --> NotifFeed[NotificationView: Feed of Alerts & Requests]
    NotifFeed --> RequestCard[Dark Glass Request Card: Requester Avatar, Bike, Target Ride]
    
    RequestCard --> Action{Organiser Action}
    Action -->|Tap 'Decline'| DeclineReq[UPDATE ride_join_requests status='declined']
    DeclineReq --> DismissCard[Card removed with animation]
    
    Action -->|Tap 'Accept'| AcceptReq[Supabase RPC: accept_ride_join_request]
    AcceptReq --> Lock[Row lock request FOR UPDATE]
    Lock --> CheckStatus{Status == 'pending'?}
    CheckStatus -->|Yes| UpdateReq[UPDATE ride_join_requests status='accepted']
    UpdateReq --> InsertRoster[INSERT into 'ride_members' status='accepted']
    InsertRoster --> ReturnUpdated[Return updated ride members payload]
    ReturnUpdated --> UIUpdate[Notification Card changes to 'Accepted' Checkmark]
    UIUpdate --> RequesterHome[Ride immediately appears on Requester's Home Screen]

    classDef done fill:#064e3b,stroke:#10b981,stroke-width:2px,color:#fff;
    class Organiser,Bell,NotifFeed,RequestCard,Action,DeclineReq,DismissCard,AcceptReq,Lock,CheckStatus,UpdateReq,InsertRoster,ReturnUpdated,UIUpdate,RequesterHome done;
```

---

## 8. Diagram 7: Ride Start & Participant Synchronization

```mermaid
flowchart TD
    subgraph Current Implementation [CURRENT IMPLEMENTATION - ISOLATED]
        A1[Organiser taps 'Start ride'] --> B1[RideStartingView: 3s Local Countdown]
        B1 --> C1[AppState.isNavigating = true]
        C1 --> D1[RideNavView: Local MapKit turn-by-turn]
        
        P1[Participant on their phone] --> P2[RideDetailsView: Button still says 'Start ride']
        P2 --> P3[Zero Alerts / Zero Sync / Unaware of Organiser Departure]
    end

    subgraph Required Implementation [REQUIRED SPECIFICATION - SYNCHRONIZED]
        A2[Organiser taps 'Start ride'] --> B2[Location Authorization Pre-flight Check]
        B2 --> C2[Supabase Mutation: UPDATE rides SET status='in_progress']
        C2 --> D2[Broadcast over Supabase Realtime Channel 'ride_session:id']
        D2 --> E2[Participant Devices receive 'RIDE_STARTED' event]
        E2 --> F2[Participant Device auto-presents 'Ride Started' Action Sheet]
        F2 --> G2[Participant taps 'Join Navigation']
        D2 --> H2[Both Devices connect to Shared Realtime Telemetry Channel]
    end

    classDef done fill:#064e3b,stroke:#10b981,stroke-width:2px,color:#fff;
    classDef missing fill:#7f1d1d,stroke:#ef4444,stroke-width:2px,stroke-dasharray: 2 2,color:#fff;

    class A1,B1,C1,D1 done;
    class P1,P2,P3,A2,B2,C2,D2,E2,F2,G2,H2 missing;
```

---

## 9. Diagram 8: Active Navigation & Telemetry Journey

```mermaid
flowchart TD
    NavEnter([Enter RideNavView]) --> InitCamera[MapCamera: 55° Pitch Cockpit Perspective]
    InitCamera --> InitPolyline[Render Cyan Route Polyline]
    InitPolyline --> LocTrack[LocationService: Track Heading & Speed]
    
    LocTrack --> ManeuverCard[NavManeuverCard: Distance & Icon update]
    LocTrack --> VoiceSynth[AVSpeechSynthesizer: Spoken Prompts]
    
    LocTrack -.->|CRITICAL BUG| FlatETA[calculateRemainingETA: Flat 45 km/h Calculation]
    LocTrack -.->|CRITICAL BUG| LockPause[Lock Screen: App Suspends & Location Stops]
    LocTrack -.->|MISSING| NoPeers[Map renders only 'You'; zero peer markers]
    
    NavEnter --> SOSButton[Hold SOS Button 3 Seconds]
    SOSButton -.->|SAFETY HAZARD| FakeSOS[Displays 'SOS BROADCAST SENT' with zero network calls]

    classDef done fill:#064e3b,stroke:#10b981,stroke-width:2px,color:#fff;
    classDef partial fill:#78350f,stroke:#f59e0b,stroke-width:2px,stroke-dasharray: 5 5,color:#fff;
    classDef missing fill:#7f1d1d,stroke:#ef4444,stroke-width:2px,stroke-dasharray: 2 2,color:#fff;

    class NavEnter,InitCamera,InitPolyline,LocTrack,ManeuverCard,VoiceSynth,SOSButton done;
    class FlatETA,LockPause partial;
    class NoPeers,FakeSOS missing;
```

---

## 10. Diagram 9: End-to-End System Journey

```mermaid
flowchart LR
    CrewPhase[1. Crew Formation<br/>Create Club & Add Members] --> PlanPhase[2. Trip Planning<br/>Pick Route, Pacing, Stops]
    PlanPhase --> InvitePhase[3. Join & Invitation<br/>Share 6-char Code & Approve Requests]
    InvitePhase --> StartPhase[4. Ride Day Start<br/>Countdown & Session Initialization]
    StartPhase --> NavPhase[5. Active Group Riding<br/>3D Navigation, Spacing, Telemetry]
    NavPhase --> PostPhase[6. Ride Completion<br/>Stats, Roster Summary, Archive]

    classDef done fill:#064e3b,stroke:#10b981,stroke-width:2px,color:#fff;
    classDef partial fill:#78350f,stroke:#f59e0b,stroke-width:2px,stroke-dasharray: 5 5,color:#fff;
    classDef missing fill:#7f1d1d,stroke:#ef4444,stroke-width:2px,stroke-dasharray: 2 2,color:#fff;

    class CrewPhase,InvitePhase done;
    class PlanPhase,StartPhase,NavPhase,PostPhase partial;
```

