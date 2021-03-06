# this solve:
# ShinyHierarchy: no visible binding for global variable 'name'
# Undefined global functions or variables:
#  . V1 name
. <- V1 <- name <- NULL
# but you need to avoid:
# - use . in the functions.
# - use nonstandar evaluation (V1, name), you need
# to use the standar evaluation alternatives like mutate_ separete_ etc_ :P


#' ShinyDummyCheck
#'
#' This function takes Shiny files themselves as inputs and tries to combine the different
#' assets presented in the ui and server files to see whether they match up.
#'
#' For now, it only works where the server and ui files are seperate (ie, it doesn't work for `app.R` yet)
#'
#' @param directory the directory or website containing the files for the Shiny App. Defaults to current working directory
#' @param ui a character vector size 1 containing the name of the UI files. defaults to "ui.R"
#' @param server a character vector size 1 containing the names of the SERVER file. defaults to "server.R"
#'
#' @return
#' Returns a dataframe with the matchings b/w ui and server files. Also spawns them in VIEW mode.
#' The structure of the table is as follows:
#' - Item - The name of the asset that maybe should be on both server.R and ui.R
#' - SrvCall - the TYPE of object that you're saying this specific item is (in server.R)
#' - isOutput  - is a binary that will specify if in server.R you wrote just `item` or `output$item`
#' - VisualCall - is the TYPE of thingie you're trying to push the item into (in ui.R).
#' - Status - Compares the SrvCall to the VisualCall, also looks at isOutput and then applies some rules to figure out if it's probably ok or not.
#'
#' The Status types that are currently being checked for are:
#' The conditions being checked are:
#' It's OK if:
#' - the server calls `render(.)` and the ui calls `Output(.)` (where . is the same Item). I also make exceptions for print==text and textoutput==verbatimtextoutput
#' - If the server calls a reactive block, the ui should not have that Item name
#'
#' It's NOT ok if:
#' - the server is calling a non-reactive and the UI doesn't have it. (this causes false positive errors for things like `observe` etc...)
#' - the server is calling a reactive block and there IS something showing up on the ui
#' - you are trying to show a non-reactive block in the ui, but forgot to put `Output$` before the item name in the server
#'
#' @examples
#' ShinyDummyCheck(directory = system.file("example", package = "ShinyTester"))
#'
#' @details You can test with your own app, go to your shiny app, make that your
#'  working directory, and then type `ShinyDummyCheck()`
#' @importFrom stringr str_split
#' @importFrom readr read_file
#' @importFrom purrr map_df
#' @importFrom dplyr filter arrange full_join
#' @export
ShinyDummyCheck <- function(directory = ".", ui = "ui.R", server = "server.R"){

  ## Change Working Directory
  # source("ui.R", chdir = T)
  # setwd(getSrcDirectory(function(x) {x}))

  ## Get server
  read_file(paste(directory,"/",server,sep="")) %>% str_split("\r?\n") -> Srv

  Srv[[1]] %>% as.data.frame() %>%
    filter(grepl("\\(\\{",.)) %>%
    filter(!grepl("#.+",.)) %>%
    arrange(.) %>% .$. %>%
    str_split(" *<- *| *= *") %>% as.data.frame %>% t %>% as.data.frame -> SrvDF
  rownames(SrvDF) <- NULL
  colnames(SrvDF) <- c("Item","SrvCall")

  SrvDF$isOutput[grepl("output\\$",SrvDF$Item)] <- "Yes"
  SrvDF$Item <- gsub("output\\$","",SrvDF$Item)
  SrvDF$Item <- gsub(" +","",SrvDF$Item)
  SrvDF$Item <- gsub("\\(outputId *\\= *","",SrvDF$Item)
  SrvDF$SrvCall <- gsub("\\(\\{","",SrvDF$SrvCall)

  ## Get ui
  read_file(paste(directory,"/",ui,sep="")) %>% str_split("\r?\n") -> Ui

  ## But remove 'outputId' and other garbage
  Ui[[1]] <-    gsub("outputId *= *|h\\d\\(|[a-zA-Z]+Panel\\(","",Ui[[1]])

  ## Now extract just the outputs
  Ui[[1]] %>% as.data.frame() %>%
    filter(grepl("Output",.)) %>%
    filter(!grepl("#.+",.)) %>%
    arrange(.) %>% .$. %>% as.character %>%
    str_split('(?<=Output)\\(') %>%
    as.data.frame %>% t %>% as.data.frame %>%
    map_df(trimws)-> UiDF

  rownames(UiDF ) <- NULL
  colnames(UiDF) <- c("VisualCall","Item")

  ## add back in "Output"

  ## Trim the stuff before or after comma
  UiDF$VisualCall <- gsub(".*?([a-zA-Z\\._]+Output).*?","\\1",UiDF$VisualCall)



  ## Do additional cleaning
  UiDF$Item <- gsub(',.+','',UiDF$Item) ## DELETE EVERYTHING AFTER FIRST PARAMETER
  UiDF$Item <- gsub('[\\"\\),]','',UiDF$Item)
  UiDF$Item <- gsub("[\\']",'',UiDF$Item)
  UiDF$Item <- gsub(' +','',UiDF$Item)
  UiDF$Item <- gsub('[\\"\\,]','',UiDF$Item)
  UiDF$Item <- gsub("[\\',\\)]",'',UiDF$Item)
  UiDF$VisualCall <- gsub('"|\\)','',UiDF$VisualCall)
  UiDF$VisualCall <- gsub('.+\\(','',UiDF$VisualCall)
  UiDF$VisualCall <- gsub(' +','',UiDF$VisualCall)

  ## Join and remove white  space
  Bof <- full_join(SrvDF,UiDF) %>%
    map_df(trimws)

  ## Conditions Good
  Bof$Status <- ""
  Bof$Status[tolower(gsub("render","",Bof$SrvCall)) ==  tolower(gsub("Output","",Bof$VisualCall))] <- "OK"
  Bof$Status[Bof$SrvCall == "reactive" & is.na(Bof$VisualCall)] <- "OK"
  Bof$Status[Bof$SrvCall == "renderPrint" | Bof$SrvCall == "renderText" &
               (Bof$VisualCall=="textOutput"|Bof$VisualCall=="verbatimTextOutput")] <- "OK"

  ## Conditions Bad
  Bof$Status[grepl("render",Bof$SrvCall) & is.na(Bof$VisualCall)] <- "Need call in UI"
  Bof$Status[Bof$SrvCall == "reactive" & !is.na(Bof$VisualCall)] <- "Reactives don't go in UI... use 'render'somethin"
  Bof$Status[grepl("render",Bof$SrvCall) & is.na(Bof$isOutput)] <- "Put 'Output' before name in server.R definition"

  # Bof %>% View
  Bof
}


#' ShinyHierarchy
#'
#' Create a hierarchical network chart that  shows the _ad hoc_ structure of your shiny Server.
#'
#'
#' @param directory the directory or website containing the files for the Shiny App. Defaults to current working directory
#' @param ui a character vector size 1 containing the name of the UI files. defaults to "ui.R"
#' @param server a character vector size 1 containing the names of the SERVER file. defaults to "server.R"
#' @param offsetReactives a boolean that specifies if the middle row (the reactives) should show up in one row or whether there
#' should be a small offset. TRUE by default.
#' @param showInternalFunctions a boolean that specifies whether to show the functions internal to each node. These are shown
#' on mouse_over in the hierarchy chart. FALSE by default.
#' @param showCommentedOutChunks a boolean that specifies whether to show the chunks that have been commented out. FALSE by default.
#' @param output a character string that specifies what kind of plot should be outputted: either "network" or "sankey" are accepted.
#'
#' @return
#' It returns a very very nice network chart with BASICALLY three-ish ROWS of nodes.
#' The first one is the UI Inputs, the middle row(s) are the reactives, and the last row are the outputs
#' being visualized. The hesitation for the second row (the reactives) is because I have introduced a small offset
#'  to each node in the middle row in order to see reactive flows into each other (if they are all in the same row,
#'  you can't really see them). You can avoid this behavior by setting the parameter offsetReactives = F.
#' @examples
#' ShinyHierarchy(system.file("example", package = "ShinyTester"))
#'
#' @details You can test with your own app, go to your shiny app, make that your
#'  working directory, and then type `ShinyHierarchy()`
#' @importFrom readr read_lines
#' @importFrom stringr str_extract_all str_extract str_trim
#' @importFrom dplyr mutate bind_rows %>% group_by slice left_join select
#' @importFrom purrr map map_chr
#' @importFrom tidyr unnest separate
#' @importFrom stats setNames runif
#' @importFrom visNetwork visNetwork visEdges visLegend visHierarchicalLayout visOptions
#' @importFrom networkD3 sankeyNetwork
#' @export
ShinyHierarchy <- function(directory=getwd(),ui="ui.R",server="server.R",
                           offsetReactives=T,showInternalFunctions=F,
                           showCommentedOutChunks=F,output="network"){

  ## Get input again
  a <- read_file(paste(directory,"/",server,sep=""))
  b <- gsub("\r?\n","",a)
  ## Identify code chunks, basically each little shiny minifunction
  Chunks <- str_extract_all(b, "[a-zA-Z0-9\\._]+ *\\<\\- *[a-zA-Z0-9\\._]+?\\(\\{.+?\\}\\)",
                            simplify = F) %>% .[[1]]
  if (length(Chunks)==0) stop("Hrm, I can't detect any chunks. I expect assignments to use '<-'... so if
                              you're using '=' or '->' assignments or 'source'ing stuff in, then that would be why.")

  ## But need to remove out commented out blocks first, which isn't easy to do above... so:
  ParsedChunks <- read_lines(paste(directory,"/",server,sep=""))

  ## Find Chunk names
  ParsedChunks <- grep("\\(\\{", ParsedChunks,value = T)
  ParsedChunks <-  str_extract(ParsedChunks,"[a-zA-Z0-9\\._]+ *\\<\\- *[a-zA-Z0-9\\._]+?\\(\\{")
  ParsedChunks <- ParsedChunks[!is.na(ParsedChunks)]


  ## clean text into a table that shows whether the chunk name and whether it's commented out or not.
  ParsedChunks <- gsub("output\\$|<.+","",ParsedChunks)
  ParsedChunksDF <- data.frame(Thingie=gsub("# *","",str_trim(ParsedChunks)),
                               CommentedOut=grepl("#",ParsedChunks),
                               stringsAsFactors = F)
  ParsedChunksDF <- ParsedChunksDF %>% arrange(CommentedOut) %>%
    group_by(Thingie) %>% slice(1)

  ## OK... now remove commented out ones if the user has selected to do so...
  ## in some cases, there are duplicates, and to that degree, we have to should keep the visible ones first


  if(showCommentedOutChunks==F){
    ChunkDF <- data.frame(Thingie=gsub(" .+","",Chunks),
                          Chunks = Chunks,
                          stringsAsFactors = F)
    ParsedChunksDF <- left_join(ChunkDF,
                                ParsedChunksDF,by="Thingie")
    Chunks <- ParsedChunksDF %>% filter(CommentedOut==F) %>% select(Chunks) %>%
      .$Chunks %>% as.character()
  }


  ## Define function that looks for some text into the Chunks
  StringFinder <- function(stringToFind){
    df <- map(Chunks,str_extract_all,stringToFind)
    df <- map(df,as.character)
    df <- df %>% as.character()
    df <-  df %>% as.matrix %>% as.data.frame(stringsAsFactors=F)
    df[["V1"]] <- gsub('c\\(|character\\(0|\\"|\\)','', df[["V1"]])
    df
  }

  InputsinChunks <- StringFinder("input.[a-zA-Z]+")

  if (length(InputsinChunks)==0) stop("Hrm, I can't detect any inputs. I expect assignments to use '<-'... so if
                              you're using '=' or '->' assignments or 'source'ing stuff in, then that would be why.")


  ## Get inputs read into each chunk
  # InputsinChunks <- map(Chunks,str_extract_all,"input.[a-zA-Z]+")
  # InputsinChunks <- map(InputsinChunks,as.character)
  # InputsinChunks <- InputsinChunks %>% as.character()
  # InputsinChunks <-  InputsinChunks %>% as.matrix %>% as.data.frame(stringsAsFactors=F)
  # InputsinChunks$V1 <- gsub('c\\(|character\\(0|\\"|\\)','',InputsinChunks$V1)

  ## Now add in the chunk name
  InputsinChunks$name <- gsub("\\(.+","",Chunks)

  ## And make into a tidy df
  InputsDF <- InputsinChunks %>%
    mutate(V1 = strsplit(V1,",")) %>%
    unnest(V1)

  InputsDF <- InputsDF %>%
    separate(name,c("ChunkName","ChunkType"),sep = "  *\\<\\- *")

  ## Now remove input from the "Input" from input type, but add it as a seperate column
  InputsDF$V1 <- gsub(".+\\$","",InputsDF$V1)
  names(InputsDF)[3] <- "Input"
  InputsDF$InputType <- "uiInput"

  ## OK! Now grab reactives that are inputs to other Chunks ####
  ## First find reactive chunks
  # ReactiveInputs <- InputsDF %>% filter(ChunkType=="reactive") %>% select(ChunkName) %>% unique %>% .$ChunkName ## THIS IS WRONG... IT ONLY TAKES REACTIVES THAT HAVE INPUTS FROM UI ONLY
  if (length(grep("eactive",Chunks))>0){
    ReactiveInputs <- str_extract_all(Chunks,".+ *\\<\\- *reactive",simplify = T)
    ReactiveInputs <- ReactiveInputs[ReactiveInputs != ""]
    ReactiveInputs <- gsub(" *<-.+","",ReactiveInputs)
    ReactiveInputs <- paste(ReactiveInputs,"\\(\\)",sep="")

    ReactivesInChunks <- map_df(ReactiveInputs,StringFinder)

    ## Now add in the chunk name
    ReactivesInChunks$name <- gsub("\\(.+","",Chunks)

    ## And remove blanks
    ReactivesDF <- ReactivesInChunks %>%
      filter(V1 != "")

    ## And split up name
    ReactivesDF <- ReactivesDF %>%
      separate(name,c("ChunkName","ChunkType"),sep = "  *\\<\\- *")

    ## Now clean up df
    ReactivesDF$V1 <- gsub("\\(","",ReactivesDF$V1)
    names(ReactivesDF)[1] <- "Input"
    ReactivesDF$InputType <- "reactive"

    ## And create final df
    BofDF <- bind_rows(InputsDF,ReactivesDF)
  } else {
    BofDF <- InputsDF
  }

  ## Now start processing data for a network chart ####

  ## First, create nodes:
  nodes <- bind_rows(setNames(BofDF[,1:2],c("Thingie","group")),
                     setNames(BofDF[,3:4],c("Thingie","group"))) %>% unique

  ## And assign node properties:
  nodes$id <- 1:nrow(nodes)
  nodes$label <- nodes$Thingie

  ## ... including setting the level. Set 1 for inputs, 2 for mid and 3 for outputs... but
  ## since the reactives feed into reactives, it doesn't look good to have all reactives be lvl 2
  ## therefore add small small noise to layer 2 to bettter see dependencies

  nodes$level=1
  if (offsetReactives==T){
    nodes$level[nodes$group=="reactive"] <- 2 + runif(sum(nodes$group=="reactive"),min = -.5,max = .5)
  } else {
    nodes$level[nodes$group=="reactive"] <- 2
  }
  nodes$level[grep("render",nodes$group)] <- 3

  #### If showInternalFunctions is true, then add as a title the functions within each node ###########################################
  ## str_extract_all(Chunks,"[a-zA-Z0-9\\._]+?(?=\\()(?!\\)|\\{)") This one should work but can't get it to respect the positive lookahead... so cheating

  if(showInternalFunctions==T){
    intFunc <- str_extract_all(Chunks,"[a-zA-Z0-9\\._]+?\\((?!\\)|\\{)")

    ## make the function calls unique (this part may be changed or parametrized if ppl want the full list includin dups in the future)
    intFunc <- map(intFunc,unique)
    intFunc <- map_chr(.x = intFunc,.f =  paste,collapse="; ")

    ## And remove the nasty parenthesis from above
    intFunc <- gsub("\\(","",intFunc)

    ## And make into a df w/ the chunk names and the func's, but let's call em title cause thats what they will need to be
    IntFuncDF <- data.frame(Thingie = gsub(" ?<-.+","",Chunks),
                            title = intFunc,stringsAsFactors = F)

    ## But protect against duplicates
    IntFuncDF <- IntFuncDF  %>%
      group_by(Thingie) %>% slice(1)

    ## Now push whatever is relevant to the nodes
    nodes <- left_join(nodes,IntFuncDF,by="Thingie")
    nodes$title <- paste(strwrap(nodes$title , width = 40,prefix = "<br>"),collapse="")
    }



  ## Now edges
  edges <- data.frame(to=nodes$id[match(x = BofDF$ChunkName,table = nodes$Thingie)],
                      from=nodes$id[match(x = BofDF$Input,table = nodes$Thingie)])

  ## Now output network or sankey
  if(output=="network"){
    visNetwork(nodes,edges) %>% visEdges(arrows = 'to') %>%
    visLegend() %>% visHierarchicalLayout()  %>%
    visOptions(highlightNearest = list(enabled = T, degree = 1, hover = T))
  } else if (output=="sankey"){
    ## make links unique
    edges <- edges %>%
      group_by(from,to) %>%
      summarize(value=n())
    ## zero indexing
    edges$from <- edges$from-1
    edges$to <- edges$to-1

    sankeyNetwork(Links=edges,Nodes = nodes,Source = 'from',NodeID = 'Thingie',
                  Target = 'to', Value = 'value',NodeGroup = 'group',fontSize = 15)

  } else {
    stop("Only 'network' or 'sankey' are accepted as outputs")
  }
}


#' #' ProcessReactives
#' #'
#' #' This function runs all the guts from reactive blocks in console (for local testing/debugging).
#' #'
#' #' For now, it only works where the server and ui files are seperate (ie, it doesn't work for `app.R` yet)
#' #'
#' #' @param directory the directory or website containing the files for the Shiny App. Defaults to current working directory
#' #' @param ui a character vector size 1 containing the name of the UI files. defaults to "ui.R"
#' #' @param server a character vector size 1 containing the names of the SERVER file. defaults to "server.R"
#' #' @param inputs a 1 row dataframe containing values for all the inputs that would be required by the reactive scripts (so as to simulate a live version of the Shiny app)
#' #'
#' #' @return
#' #' Returns nothing, but loads all items into memory
#'
#' #' @examples
#' #' ProcessReactives(directory = system.file("example2", package = "ShinyTester"))
#' #'
#' #' @details You can test with your own app, go to your shiny app, make that your
#' #'  working directory, and then type `ProcessReactives()`
#' #' @importFrom stringr str_extract_all str_extract str_trim str_split
#' #' @importFrom readr read_file
#' #' @export
#'
#' ProcessReactives <- function(directory=getwd(),ui="ui.R",server="server.R",
#'                             inputs=inputs){
#'
#'   ## Get input again
#'   a <- read_file(paste(directory,"/",server,sep=""))
#'   b <- gsub("\r?\n","",a)
#'   ## Identify code chunks, basically each little shiny minifunction
#'   Chunks <- str_extract_all(b, "[a-zA-Z0-9\\._]+ *\\<\\- *[a-zA-Z0-9\\._]+?\\(\\{.+?\\}\\)",
#'                             simplify = F) %>% .[[1]]
#'   if (length(Chunks)==0) stop("Hrm, I can't detect any chunks. I expect assignments to use '<-'... so if
#'                               you're using '=' or '->' assignments or 'source'ing stuff in, then that would be why.")
#'
#'   ## Identify only the reactive chunks
#'   Chunks <- Chunks[grep("reactive\\(",Chunks)]
#'
#'   ## get only the guts
#'   Chunks2 <- str_extract(string = Chunks,"(?<=\\(\\{).+(?=\\}\\))")
#'
#'   ## And make stuff evaluatable by replacing multiple space w/ semicolon, however, except the first one.
#'   Chunks3 <- gsub("   +","; ",str_trim(Chunks2),perl=T)
#'
#'   ## But deal w/ pipes
#'   Chunks4 <- gsub("\\%;","\\%",Chunks3)
#'
#'   for(i in 1:length(Chunks4)){
#'       # eval(parse(text = Chunks4[i]))
#'     eval(parse(text = str_split(Chunks4[i],";")[[1]]))
#'   }
#' }
