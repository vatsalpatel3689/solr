package org.apache.solr.search;

import java.lang.invoke.MethodHandles;

import org.apache.lucene.index.LeafReaderContext;
import org.apache.lucene.search.LeafCollector;
import org.apache.lucene.search.ScoreDoc;
import org.apache.lucene.search.ScoreMode;
import org.apache.lucene.search.TopDocs;
import org.apache.lucene.search.TopDocsCollector;
import org.apache.lucene.search.TotalHits;
import org.apache.solr.common.SolrException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Optimised TopDocsCollector for queries comprising of only filter-queries.
 */
public class NonReRankingDocSetTopDocsCollector extends TopDocsCollector<ScoreDoc> {
    private static final Logger log = LoggerFactory.getLogger(MethodHandles.lookup().lookupClass());

    /** matchedDocSet (intersection of all filters) */
    private DocSet matchedDocSet;
    private int totalHits;

    public NonReRankingDocSetTopDocsCollector() {
        super(null);
    }

    public int getTotalHits() {
        return totalHits;
    }

    @Override
    public LeafCollector getLeafCollector(LeafReaderContext context) {
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
            int reRankScoreDocsLength = Math.min(totalHits, howMany);
            ScoreDoc[] reRankScoreDocs = new ScoreDoc[reRankScoreDocsLength];

            if (matchedDocSet == null) {
                return new TopDocs(new TotalHits(this.totalHits, TotalHits.Relation.EQUAL_TO), reRankScoreDocs);
            }

            DocIterator iterator = matchedDocSet.iterator();
            for (int i=0; i<reRankScoreDocsLength; i++) {
                reRankScoreDocs[i] = new ScoreDoc(iterator.nextDoc(), 0.0f);
            }

            return new TopDocs(new TotalHits(this.totalHits, TotalHits.Relation.EQUAL_TO), reRankScoreDocs);
        } catch (Exception e) {
            log.error("exception during topDocsCollection", e);
            throw new SolrException(SolrException.ErrorCode.BAD_REQUEST, e);
        }
    }
}