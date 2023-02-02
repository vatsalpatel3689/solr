package org.apache.solr.search;

import java.io.IOException;
import java.lang.invoke.MethodHandles;
import java.util.Arrays;
import java.util.Map;
import java.util.Set;

import com.carrotsearch.hppc.IntIntHashMap;
import org.apache.lucene.index.LeafReaderContext;
import org.apache.lucene.search.IndexSearcher;
import org.apache.lucene.search.LeafCollector;
import org.apache.lucene.search.Rescorer;
import org.apache.lucene.search.ScoreDoc;
import org.apache.lucene.search.ScoreMode;
import org.apache.lucene.search.TopDocs;
import org.apache.lucene.search.TopDocsCollector;
import org.apache.lucene.search.TotalHits;
import org.apache.lucene.util.BytesRef;
import org.apache.solr.common.SolrException;
import org.apache.solr.handler.component.QueryElevationComponent;
import org.apache.solr.request.SolrRequestInfo;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class DocSetTopDocsCollector extends TopDocsCollector<ScoreDoc> {
    private static final Logger log = LoggerFactory.getLogger(MethodHandles.lookup().lookupClass());

    /** matchedDocSet (intersection of all filters) */
    private DocSet matchedDocSet;
    private int totalHits;

    final private IndexSearcher searcher;
    final private int reRankDocs;
    final private Set<BytesRef> boostedPriority; // order is the "priority"
    final private Rescorer reRankQueryRescorer;

    public DocSetTopDocsCollector(int reRankDocs,
                                  Rescorer reRankQueryRescorer,
                                  IndexSearcher searcher,
                                  Set<BytesRef> boostedPriority) {
        super(null);
        this.reRankDocs = reRankDocs;
        this.boostedPriority = boostedPriority;
        this.searcher = searcher;
        this.reRankQueryRescorer = reRankQueryRescorer;
    }

    public int getTotalHits() {
        return totalHits;
    }

    @Override
    public LeafCollector getLeafCollector(LeafReaderContext context) throws IOException {
        // it is not expected to be called, instead setMatchedDocSet() is called with matched docs.
        return null;
    }

    public void setMatchedDocSet(DocSet matchedDocSet) {
        this.matchedDocSet = matchedDocSet;
        // expensive to compute, computing once and setting it.
        this.totalHits = matchedDocSet != null ? matchedDocSet.size() : 0;
    }

    @Override
    public ScoreMode scoreMode() {
        return ScoreMode.COMPLETE_NO_SCORES;
    }

    public TopDocs topDocs(int start, int howMany) {

        try {
            int reRankScoreDocsLength = Math.min(totalHits, reRankDocs);
            ScoreDoc[] reRankScoreDocs = new ScoreDoc[reRankScoreDocsLength];

            if (matchedDocSet == null) {
                return new TopDocs(new TotalHits(this.totalHits, TotalHits.Relation.EQUAL_TO), reRankScoreDocs);
            }

            // NOTE:fkltr L1 rankAndLimit can be moved here, either using stored L1 or using cacheLookup. It will save extra space allocation.
            // But for that to happen explore has to be solved here.
            // And for grouping-scenario it will be tricky to solve it here As grouping is getting ever complex and not very abstract concept for us.
            DocIterator iterator = matchedDocSet.iterator();
            for (int i=0; i<reRankScoreDocsLength; i++) {
                reRankScoreDocs[i] = new ScoreDoc(iterator.nextDoc(), 0.0f);
            }

            TopDocs mainDocs = new TopDocs(new TotalHits(this.totalHits, TotalHits.Relation.EQUAL_TO), reRankScoreDocs);

            TopDocs rescoredDocs = reRankQueryRescorer
                    .rescore(searcher, mainDocs, mainDocs.scoreDocs.length);

            //Lower howMany to return if we've collected fewer documents.
            howMany = Math.min(howMany, rescoredDocs.scoreDocs.length);

            if(boostedPriority != null) {
                SolrRequestInfo info = SolrRequestInfo.getRequestInfo();
                Map requestContext = null;
                if(info != null) {
                    requestContext = info.getReq().getContext();
                }

                IntIntHashMap boostedDocs = QueryElevationComponent.getBoostDocs((SolrIndexSearcher)searcher, boostedPriority, requestContext);

                float maxScore = rescoredDocs.scoreDocs.length == 0 ? Float.NaN : rescoredDocs.scoreDocs[0].score;
                Arrays.sort(rescoredDocs.scoreDocs, new ReRankCollector.BoostedComp(boostedDocs, mainDocs.scoreDocs, maxScore));
            }

            if(howMany == rescoredDocs.scoreDocs.length) {
                return rescoredDocs; // Just return the rescoredDocs
            } else if(howMany > rescoredDocs.scoreDocs.length) {
        /*
        Solr supports the use-case where you can have rescoredDocs < howMany.
        In this scenario it lays down the initial docs and then overlays with rescored docs.
        We don't want this to happen as original scores and rescored scores are not comparable for us.
        Moreover, we also support two-level ranking in rescorer where docs are trimmed after first step, so this situation will arise almost every time.
        Thereby returning only rescoredDocs in this case.
        Side-effect of this is that we may be returning less docs than actually queried for even if there are enough matching documents,
        it will happen when matchedDocs > howMany > rescoredDocs.
         */
                return rescoredDocs;
            } else {
                // It is best to avoid this case, we should have and l2Limit should always be <= howMany.
                // If we arrive here, it involves an array-copy and more importantly it just takes first howMany elements and
                // absolutely disregards any ordering intended by rescorer (like no ordering, custom group-ordering, explore etc.)

                // We've rescored more then we need to return.
                ScoreDoc[] scoreDocs = new ScoreDoc[howMany];
                System.arraycopy(rescoredDocs.scoreDocs, 0, scoreDocs, 0, howMany);
                rescoredDocs.scoreDocs = scoreDocs;
                return rescoredDocs;
            }
        } catch (Exception e) {
            log.error("exception during topDocsCollection", e);
            throw new SolrException(SolrException.ErrorCode.BAD_REQUEST, e);
        }
    }
}